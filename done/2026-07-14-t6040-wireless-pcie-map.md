# T6040 J614s PCIe + wireless map (2026-07-14)

## Result

The J614s internal PCIe topology is now mapped end to end from the paired ADT
to the existing Linux drivers. A separate kernel/DT build exists for the later
Linux-enumeration stage. The initial map and build required no target MMIO; the
subsequent first live result is recorded below.

The target identity is **Mac16,8 / J614sAP, MacBook Pro 14-inch M4 Pro**.  It is
not Mac14,8 and it is not the 16-inch chassis.

## Populated topology

`/arm-io/apcie0` is `apcie,t6040`, with four hardware ports and two populated
bridges:

| Port | ADT child | Device | Linux ID | PERST# | CLKREQ# | Link cap | DART |
|---|---|---|---|---|---|---|---|
| 0 | `pci-bridge0` | BCM4388 WiFi + Bluetooth | `14e4:4434`, `14e4:5f72` | GPIO 4 | GPIO 0 fn 2 | Gen2 | `0x410000000`, IRQ 1724 |
| 1 | `pci-bridge1` | Genesys Logic GL9755 SD reader | `17a0:9755` | GPIO 5 | GPIO 1 fn 2 | ADT bridge cap Gen1 | `0x411000000`, IRQ 1733 |
| 2 | absent | unpopulated | — | GPIO 6 (template only) | — | — | absent |
| 3 | absent | unpopulated | — | GPIO 7 (template only) | — | — | absent |

The saved ADT identifies `/product/wifi-chipset = "4388"` and
`/arm-io/wlan/module-instance = "mriya"`.  Linux already has both required PCI
IDs and the BCM4377-family Bluetooth driver explicitly supports BCM4388.  The
board type `apple,mriya` in the bring-up DT is an evidence-backed inference
from that module-instance, following existing Apple board DT convention.
m1n1 will copy the target's MAC addresses, antenna SKU, WiFi calibration, and
Bluetooth calibration into the aliased `wifi0`/`bluetooth0` nodes at handoff.

## T6040 host-controller register map

Shared ADT registers:

| Index | CPU PA | Size | Role |
|---|---:|---:|---|
| 0 | `0x1cb0000000` | `0x10000000` | ECAM |
| 1 | `0x414000000` | `0x4000` | root controller |
| 2 | `0x417000000` | `0x40000` | PHY common |
| 3 | `0x417040000` | `0x28000` | PHY IP |
| 4 | `0x416000000` | `0x1000000` | AXI |
| 5 | `0x415046200` | `0x4000` | CIO3 PLL core |
| 6 | `0x415044000` | `0x4000` | PCIe clock generator |

The remaining 28 entries are four repetitions of seven registers.  Linux uses
the first (`port`) and third (`phy`) entry for each port:

| Port | Port block | LTSSM | Port PHY | PHY IP | intr2axi |
|---|---:|---:|---:|---:|---:|
| 0 | `0x410028000` | `0x41003c000` | `0x417020000` | `0x417048000` | `0x410024000` |
| 1 | `0x411028000` | `0x41103c000` | `0x417024000` | `0x417050000` | `0x411024000` |
| 2 | `0x412028000` | `0x41203c000` | `0x417028000` | `0x417058000` | `0x412024000` |
| 3 | `0x413028000` | `0x41303c000` | `0x41702c000` | `0x417060000` | `0x413024000` |

Controller IRQs are 1723/1732/1741/1750.  The 32 MSI vectors start at AIC IRQ
2071.  The outbound windows are:

- 64-bit prefetchable: bus/CPU `0xbc0000000`, size `0x20000000`;
- 32-bit memory: bus `0x80000000`, CPU `0xb80000000`, size `0x40000000`.

T6040's Linux-visible port registers use the T602x layout: PERST at `0x82c`,
RID2SID at `0x3000`, and MSIMAP at `0x3800`.  The provisional DT therefore uses
`"apple,t6040-pcie", "apple,t6020-pcie"`; the existing driver binds through the
fallback.

## Resolved clock/PLL windows

The old PCIe plan stopped correctly because the two new tunable groups could
not be assigned to reg[5]/reg[6] from the ADT alone.  Static disassembly of the
paired local macOS kernelcache resolves this without probing MMIO:

- `ApplePCIEBaseT8132::dtRegMapCio3PllIndex()` reads object slot `0x2c9`;
- `ApplePCIEBaseT8132::dtRegMapPcieClkgenIndex()` reads slot `0x2ca`;
- `AppleT6040PCIe::start()` assigns `5` to `0x2c9` and `6` to `0x2ca`.

Therefore:

- `apcie-cio3pllcore-tunables` targets ADT reg[5], `0x415046200`;
- `apcie-pcieclkgen-tunables` targets ADT reg[6], `0x415044000`.

The exact newly enabled ADT RMW operations are:

| Address | Size | Mask | Value |
|---:|---:|---:|---:|
| `0x415046200` | 4 | `0x00000a0b` | `0x00000a01` |
| `0x415046224` | 4 | `0x00000c00` | `0x00000800` |
| `0x415046228` | 4 | `0x00000f00` | `0x00000b00` |
| `0x415046238` | 4 | `0x00000020` | `0x00000000` |
| `0x41504624c` | 4 | `0x000000ff` | `0x00000095` |
| `0x4150462e8` | 4 | `0x000e0000` | `0x00020000` |
| `0x415046300` | 4 | `0x00ffffff` | `0x000b40b4` |
| `0x415044000` | 4 | `0x000003e0` | `0x00000220` |

These are ADT data applied as `(old & ~mask) | value`, not invented constants.

## Code and build state

m1n1 baseline support applies the two proven T6040-only groups and continues
through the existing T6031/T8122 PHY and port sequence:

- main: `eb23c423` (`pcie: initialize T6040 clock and PLL blocks`);
- curated `t6040-bringup`: `da1791a0` (same code-only change).

The current diagnostic heads temporarily trace each T6040 tunable and return
after the clock groups: main `81da3522`, curated `b95da002`. They do not reach
the PHY/port sequence.

Both m1n1 trees build cleanly.  The Linux bring-up source is deliberately kept
separate at `dts/t6040-j614s-dcuart-pcie.dts`; it includes GPIO/pinctrl, all four
host resources, the two populated root ports, both DARTs, BCM4388 child nodes,
and the GL9755 child node.  `scripts/t6040-build-pcie.sh` builds it in a clean,
dedicated container tree with `PCIE=1` so stale NVMe diagnostics cannot leak
into the image.

The host controller, GPIO, and DART drivers are built in. WiFi, Bluetooth, and
SD endpoint drivers are configured as modules but are not included in the PCIe
image's initramfs. This keeps the later Linux-enumeration stage bounded to host
link, DART probe, and PCI config space; building/loading endpoint modules with
their normal dependency set is a separate follow-up.

The kernel image and DT compile cleanly with the normal build. Schema checking
is not claimed: the container's installed `dt-validate` command is incompatible
with the kernel's `dtbs_check` invocation. Endpoint modules are configured but
were deliberately not built or staged for this milestone.

Prepared Linux-enumeration artifacts:

- `Image-pcie`: `e7dcfcc1dea997ca53624ba50e50b210472dc63b003f17a5040265176351107a`;
- `t6040-j614s-dcuart-pcie.dtb`: `258ca9e52284864498dde10cabc807f94990528cfc7e3dad98356bf999ff2eb2`;
- `initramfs-dcuart-pcie.cpio.gz`: identical to the proven module-free
  DockChannel BusyBox initramfs, hash
  `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`;
- `System.map-pcie`: `350d8bdeb1f6e88b72591cc68381a68ff97d615b574e3f9fb4e995f2bb8396ff`.

## Complete write review

`scripts/t6040-pcie-write-plan.py` consumes the committed raw J614s ADT without
connecting to the target and expands the actual T6040 path at m1n1 `eb23c423`.
The checked-in result is `2026-07-14-t6040-pcie-write-manifest.tsv`, SHA-256
`a134c540784cca94a44e2392e0060de4249fec01d653af87c352bd0f82e6265e`.
It contains 1,571 ordered operations at 1,459 distinct addresses:

- 19 recursive PMGR RMWs, including repeated parent visits exactly as m1n1
  executes them;
- 91 controller operations and 241 shared-PHY operations;
- 610 operations for each populated port, including every RID2SID/MSIMAP loop
  element and both ports' ADT config/DBI tunables.

Every row provides address, access size, operation, mask, and value. `WRITE`
replaces the full value; `RMW` is `(old & ~mask) | value`; `SET` and `CLEAR`
state the exact bit operand. The source ADT hash is
`87f5c391b0fc722bdaa0fdca468f160bccf1becaa2f81cec052c481b7c98f195`.
Regenerate it with:

```sh
git -C ~/Code/linux show feature/m4-m5-minimal-device-trees:j614s.adt \
  | scripts/t6040-pcie-write-plan.py \
  > done/2026-07-14-t6040-pcie-write-manifest.tsv
```

## First live result

The maintainer approved one m1n1-only attempt using `eb23c423` and the
PCIe-free base DT. The clean retry reached the controller on 2026-07-14:

```text
pcie: Error getting node /arm-io/apcie
pcie: Initializing t6040 PCIe controller
pcie: ADT uses 7 reg entries per port
pcie: No common tunables
```

Output then stopped. PMGR recursion, all 77 AXI tunables, and the RC `+0x4`
write necessarily completed before the last line. The exact later boundary is
not yet known because the original build did not print around local tunables;
the stall could be in either new clock group or the following pre-poll PHY
tunables. An asynchronous fault is plausible but not proven.

The uploader timed out without a proxy reply. The sanctioned HPM DebugUSB warm
reboot recovered the target to a healthy `Running proxy`; the opaque sequence
was not retried. Linux never handed off, no endpoint/port result was observed,
and no NVMe or user-storage access occurred. Transcript:
`logs/t6040-console-20260714-pcie-stage1.log`, SHA-256
`b850b08a6ce2b40a2067324dabacaa52102f6b4c07b1c7b045237f64fb2a5398`.

## Bounded follow-up gate

The prepared diagnostic changes observation and bounds execution:

- m1n1 main `81da3522`; tracing code `47732d50`, stop-before-PHY code
  `25dc42a2`;
- curated equivalents `06b6a306` and `b95da002`;
- main `m1n1.bin` SHA-256
  `d6351b32e6e344e40c6dbecda7ad4e09bf57587bb02b5022cc9f27a494e951f3`;
- every T6040 local tunable prints its address/size/mask/value before the RMW
  and prints `done` only after the access returns;
- after CIO3 entries 98–104 and clkgen entry 105, m1n1 returns before manifest
  entry 106. No PHY, port, PERST#, RID2SID, MSIMAP, or Linux PCIe write can run.

The exact next-attempt write set is
`2026-07-14-t6040-pcie-clock-diagnostic.tsv`, SHA-256
`85d3472fcf4ccb17379df1aaf46faa9b714cedece6fe65fd484e6dad4081fd93`.
It is the first 105 operations of the full manifest: 19 PMGR RMWs, 77 proven
AXI RMWs, one RC write, seven CIO3 RMWs, and one clkgen RMW.

This diagnostic has **not** run and requires separate explicit approval. It
must boot the PCIe-free base DT. If a tunable faults, its pre-write line is the
last output; if all eight new entries return, m1n1 prints the diagnostic-stop
message and the base Linux image may hand off normally.

## Full-path gate

`pcie_init()` is a kboot-time invasive operation. A complete target boot remains
**unattempted and gated**. It will apply the full existing ADT-derived
AXI/PHY/PHY-IP/bridge tunable sets and the reused T6031/T8122 clock/reset/port
sequence. After the bounded trace is understood, use two further stages:

1. Boot a corrected full m1n1 path with the current PCIe-free base DT. The Image
   and initramfs are previously boot-proven; the concurrently rebuilt DT differs
   from the older build-15 hash but contains no PCIe host node. Current hashes:
   Image `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`,
   DTB `e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`,
   initramfs `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`.
2. Only after reviewing that result, boot the prepared PCIe DT for Linux
   host/DART and config-space enumeration. Endpoint modules remain absent.

Neither stage may access the NVMe namespace or mount/repair/format any storage.
