# T6040 guarded PCIe clock diagnostic

Prepared 2026-07-14. **Not approved or run.** This is the first write-bearing
PCIe retry after the upper log-buffer guard proved that every earlier traced
`[70]` SError was a logging artifact.

## Exact build

- m1n1 main commit: `f46d6e35` (`v1.6.0-78-gf46d6e35`)
- main `build/m1n1.bin` SHA-256:
  `8fd7319047187f9ca05a6924462a4f24360fcc1d9e4279b089dc83a5acb05744`
- curated commit: `f8725409`
- curated `build/m1n1.bin` SHA-256:
  `2675c12d5305f2c585d008affaa6d1593ffc4463a7dbd1ca7f747561e0a128f2`
- main and curated relevant sources are byte-identical.

Use only the main binary. Boot the proven PCIe-free base DTB, SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Exact write boundary

The ordered PCIe operation set is unchanged from
`2026-07-14-t6040-pcie-clock-diagnostic.tsv`, SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`:

- operations 1–12: recursive PMGR RMWs for clock gates 0–6;
- operations 13–89: 77 ADT-supplied AXI RMWs;
- operation 90: the existing RC `+0x4` write;
- operations 91–97: seven CIO3 PLL RMWs;
- operation 98: one PCIe clkgen RMW;
- operations 99–105: recursive PMGR RMWs ending at the late
  `APCIE_PHY_SW` gate.

The sequence matches Apple's gate order. Every traced tunable RMW retains its
`dsb sy` and read-only `L2C_ERR_STS` sample; a nonzero sample aborts without
clearing status. The proven 16 KiB upper guard remains above the active stage-2
log ring.

The controller returns immediately after operation 105. It cannot execute
operation 106, the first PHY write, or reach PHY polling, ports, PERST#,
RID2SID/MSIMAP, or Linux PCIe. The base DT has no PCIe host node. NVMe and
storage remain outside the path.

## Approval gate

This is a write-bearing target binary and requires fresh explicit approval for
one live run of the main binary and manifest hashes above. Stop after that
outcome and recover through the sanctioned DebugUSB helper if necessary. Do not
mount, repair, format, or otherwise access storage.
