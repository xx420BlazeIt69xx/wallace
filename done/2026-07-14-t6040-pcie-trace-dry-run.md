# T6040 PCIe zero-write trace control

Prepared 2026-07-14. **Not approved or run.** This control distinguishes a
console/trace-volume artifact from the delayed PCIe SError seen in the three
write-bearing traces.

## Exact build

- m1n1 main commit: `3e772779` (`v1.6.0-72-g3e772779`)
- main `build/m1n1.bin` SHA-256:
  `c9296b8d1ca146a32c7a1ba1bf17b7091281588ab90d16a69f0718c5a8fa04ea`
- curated commit: `841ca99d`
- curated `build/m1n1.bin` SHA-256:
  `6bde25019f51b9cb92f999394da2885cc91c01bcefd1b0529ef328cf4dc67e3d`
- main and curated `src/pcie.c`, `src/tunables.c`, and `src/tunables.h` are
  byte-identical; their build tags account for the binary-hash difference.

Use only the main binary for a live control. Boot the proven PCIe-free base DTB,
SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Static write boundary

This is zero **PCIe** MMIO, not a claim that ordinary boot contains no hardware
access. The already boot-proven MCC/cache/clock/USB kboot setup still precedes
`pcie_init()`.

For the T6040 controller, `pcie_init_controller()` performs only ADT memory
lookups through the existing port-register-count validation. It then calls
`tunables_trace_local_dry_run()` and returns before:

- `pmgr_adt_power_enable_index()` or any PCIe clock-gate RMW;
- the first AXI controller read or write;
- RC, CIO3, clkgen, PHY, port, PERST#, RID2SID, or MSIMAP access.

The dry-run helper reads the AXI property and reg base from the in-memory ADT,
calculates each displayed address, and prints the same 77 pre/`done` line pairs.
Its internal `write=false` path cannot call `mask8/16/32/64`, does not execute
the barrier/L2C sampling used by the write trace, and performs no MMIO read.

There is deliberately no extra marker before entry `[0]`, so the console stream
from `pcie: Initializing t6040 PCIe controller` through the trace pairs matches
the previous traces byte-for-byte. A completion marker is printed only after
entry `[76]`, then the controller returns. The base Linux boot may continue;
its DT has no PCIe host node and is already boot-proven.

## Interpretation and approval gate

- SError at the same output-volume boundary: the traced `[70]` boundary is a
  logging/console artifact; debug that path before PCIe MMIO.
- All 77 pairs and the completion marker print: trace volume is exonerated;
  prepare an independently approved AXI prefix-and-hold bisection.

This is a new target binary and requires explicit approval for one live run of
the main binary hash above. Stop after that outcome. Preserve DebugUSB reader
discipline and use the sanctioned recovery helper if needed. NVMe and all
namespace/mount/repair/format operations remain out of scope.
