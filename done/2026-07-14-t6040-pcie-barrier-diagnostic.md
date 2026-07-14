# T6040 PCIe AXI barrier diagnostic

Prepared 2026-07-14. **Not approved or run.** This is the next bounded live
diagnostic after the Apple-accurate staged-clock run repeated the asynchronous
SError after AXI tunable `[70]`.

## Exact build

- m1n1 main commit: `88ce1ee3` (`v1.6.0-68-g88ce1ee3`)
- main `build/m1n1.bin` SHA-256:
  `2997b07647007f99df6ad094a2da55d66a9f7accd6758bb134d3fa92b76d0c72`
- curated commit: `82d99f17`
- curated `build/m1n1.bin` SHA-256:
  `463219a9d9a26f43ee8a92ddb7ce8ec23d55f61f81cfd4a49051d7c139fbe5f1`
- the two `src/tunables.c` and `src/pcie.c` files are byte-identical; different
  build tags account for different binary hashes.

Use the main binary for the live run. Boot only the previously proven PCIe-free
base DTB, SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Bounded behavior

The MMIO operation set and order are unchanged from
`2026-07-14-t6040-pcie-clock-diagnostic.tsv`, SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`:

- 12 recursive PMGR RMWs for clock gates 0–6;
- 77 ADT-supplied AXI RMWs and one RC write;
- only if those complete, seven CIO3 RMWs and one clkgen RMW;
- only if those complete, seven recursive PMGR RMWs ending at the late
  `APCIE_PHY_SW` gate.

The diagnostic still returns before operation 106, the first PHY write. It
cannot reach PHY initialization, ports, PERST#, RID2SID/MSIMAP, Linux PCIe, or
storage.

The only new behavior is CPU-side observation around each traced tunable set:

1. `dsb sy`, then read `SYS_IMP_APL_L2C_ERR_STS` before the first RMW;
2. after every existing RMW, `dsb sy`, then read the same status register;
3. if the read is nonzero, print the property/index and return immediately;
4. never clear or write the L2C error-status register.

The pre-set sample separates a pending error from the preceding PMGR clock
work. Each post-RMW barrier forces that transaction to complete before the
read-only status sample. If the asynchronous exception arrives at the barrier,
the last pre-write trace line still identifies the exact attempted RMW.

## Approval and recovery gate

This build changes timing and has not inherited approval from any earlier run.
Before one live attempt, obtain explicit approval for the main binary hash and
unchanged 105-operation manifest hash above. Preserve the standard DebugUSB
reader discipline, stop after one outcome, and use the sanctioned recovery
helper if the proxy disappears. NVMe and all namespace/mount/repair/format
operations remain out of scope.
