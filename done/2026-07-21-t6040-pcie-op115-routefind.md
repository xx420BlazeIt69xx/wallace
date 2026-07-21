# T6040 PCIe op-115 route-finding — the PHY-IP aperture precondition (2026-07-21)

Ticket 058 (offline, P1, pcie track). Continues
`done/2026-07-14-t6040-pcie-op115-static-analysis.md` and the read-only
isolation result (`done/2026-07-14-t6040-pcie-op115-read-result.md`): the first
PHY-IP access hangs on its **read** side, so a precondition that makes the
`reg[3]` PHY-IP aperture (phys `0x417040000`) respond to reads is not satisfied
at m1n1's op-115 point. This ticket finds what that precondition is. Static
only; no rig, no MMIO. A changed live sequence still needs a fresh manifest,
cross-review, and CJ approval.

## m1n1 side — exactly what state the controller is in at the hang (verified)

From `~/Code/m1n1/src/pcie.c` (branch `main`), `regs_t6040`:

```
.type = APCIE_T6031, .compat = APCIE_T8122, .shared_reg_count = 7,
config_idx=0  rc_idx=1  phy_common_idx=2  phy_idx=2  phy_ip_idx=3  axi_idx=4
PHY_STRIDE=0x4000  PHYIP_STRIDE=0x40000
```

So t6040 is driven by the T8122/T6031 template. Register apertures (ADT
`reg[]`, `/arm-io` bus base `0x3_00000000`): `phy`/`phy_common` = `reg[2]`
(`0x417008000`), **`phy_ip` = `reg[3]` (`0x417040000`)**, `axi` = `reg[4]`.

The PHY bring-up preceding op-115, in order, and **which aperture each touches**:

| # | m1n1 action | aperture | notes |
|---|---|---|---|
| — | AXI / common / CIO3-PLL / PCIe-clkgen tunables | reg[4], reg[1], reg[5], reg[6] | ops ≤70, proven |
| — | enable T6040 PHY clock gate `APCIE_T6040_PHY_CLOCK_GATE_IDX` (=7) | pmgr | `pmgr_adt_power_enable_index` |
| — | `apcie-phy-tunables` (controller PHY) | **reg[2]** | via `phy_idx=2` |
| — | poll `phy_common+0x000` bit31 (100 MHz refclk) | **reg[2]** | `APCIE_PHYCMN_CLK_100MHZ` |
| — | per-phy: set `CLK0REQ`, poll `CLK0ACK`; set `CLK1REQ`, poll `CLK1ACK` | **reg[2]** | `phy_base+0x000`, BIT(0..3) |
| — | clear `RESET` (BIT7) at `phy_base+0x000`; `udelay(1)` | **reg[2]** | reset release |
| 114 | `set32(phy_base+4, 0x01)` | **reg[2]** | the `compat==T8122` "pre-tunable control" |
| — | fuse loop | reg[3] | **SKIPPED — `fuse_bits==NULL` for the t6040/t8122 selector** |
| **115** | read first `apcie-phy-ip-pll-tunables` entry at `phy_ip_base+0x90` | **reg[3]** | **first reg[3] access → HANGS** |

Two facts this pins down:

1. **Every operation before op-115 touches `reg[2]` (or pmgr/other apertures),
   never `reg[3]`.** Because `fuse_bits==NULL` for t6040 (confirmed at
   `src/pcie.c` fuse-selector: `apcie,t6040 → fuse_bits = NULL`), the fuse-loop
   `mask32(phy_ip_base…)` that *would* be the first reg[3] touch on t8103/t600x
   is skipped. So op-115 is unambiguously the **first** `reg[3]` access, and the
   read-side hang means the aperture itself is not live yet — not a mid-sequence
   corruption.
2. m1n1's whole `reg[3]` ungate assumption is inherited from the T8122/T6031
   template: it releases clocks/reset on `reg[2]` and the `+4=0x01` control, and
   expects `reg[3]` to answer. On t6040 that assumption fails.

The leading hypothesis is therefore: **t6040 has a PHY-IP (`reg[3]`) ungate —
a clock-enable, power/reset de-assert, or aperture-enable — that lives outside
the `reg[2]` CLK0/CLK1/RESET/`+4` sequence, and Apple performs it before its
first `_readPhyIPReg`.** The candidate mechanisms to confirm from Apple's driver
are: (a) an extra register write distinct from the reg[2] sequence; (b) a
different value/offset for the `+4` control on t6040; or (c) an additional pmgr
clock-gate index beyond `IDX 7`.

## Apple side — the precondition

<!-- FILLED FROM THE DISASSEMBLY TRACE OF ApplePCIEBaseT8132::configure /
     _enableRootComplex / _initializePhy (AppleT6040PCIe kext, T6041 mac16j
     kernelcache). Every address grounded in the binary; verified independently
     before any manifest change. -->

_(pending disasm agent + independent address verification)_

## Source

Paired T6041 target kernelcache `kernelcache.release.mac16j`
(Darwin 24.6.0, `xnu-11417.140.69.710.16`, `RELEASE_ARM64_T6041`),
SHA-256 `d5deb3335ff709bf9b487b975838925bf6a43b06b23bc7e920e61c5f0f0983a1`,
from this host's Preboot `restore-staged`. `AppleT6040PCIe` kext extracted with
`ipsw kernel extract`; symbols intact. No Apple binary committed.
