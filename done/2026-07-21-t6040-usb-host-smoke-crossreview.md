# T6040 USB2-host smoke — independent cross-review (2026-07-21, claude)

Second-agent review of Sol's pre-approval packet
`done/2026-07-21-t6040-usb-host-smoke-preflight.md`, per COORDINATION.md §"Cross-agent
review before approval" and the non-negotiables in `~/Code/m1n1/AGENTS.md`.

**Verdict: PASS — no blocking issues. Safe for the SMOKE boot as specified.**

> Scope note (added on re-record): this review covers the **all-three-ports**
> `t6040-j614s-dcuart-usb-host.dtb` (`47b01f9e…`) pinned in the preflight. If the
> smoke is re-scoped to a single-port DT after ticket 057's port-map capture, the
> kernel/initramfs findings below carry over unchanged, but the new DTB needs a
> short delta re-check (node statuses only) before approval. This file was first
> written earlier on 2026-07-21 and disappeared from `done/` during concurrent
> agent activity; re-recorded verbatim with this note.

## What was verified (against the actual artifacts, not just the write-up)

| Check | Method | Result |
|---|---|---|
| All 6 live inputs hash-pinned | `shasum -a 256 -c linux-build-out/t6040-usb-host-smoke.sha256` | OK (m1n1 bin, Image, dtb, initramfs, System.map, config) |
| Internal NVMe cannot probe | decompiled the DTB (`scripts/dtc`) | `nvme@40dcc0000`, SART, and the ANS mailbox `mailbox@409608000` (phandle `0x57`, the one the nvme node references) are all `status = "disabled"` |
| NVMe not auto-loaded | `.config` | `CONFIG_NVME_CORE`/`BLK_DEV_NVME`/`NVME_APPLE` all `=m` (modular) — belt-and-suspenders with the disabled node |
| No stray enabled storage coprocessor | DTB | the only `okay` ASC mailbox is `mailbox@514608000` (phandle `0x5a`), a non-storage coprocessor unrelated to ANS |
| No blind MMIO | read `patches/t6040-dwc3-apple-force-host.patch` | probe-time `dwc3_apple_init(HOST)` only; no register pokes |
| No SPMI/PMU/NVRAM/charger writes | DTB + patch | the `spmi` hits are PMGR power-domain *labels* (`nub_spmiN`), not a writable SPMI transport; nothing new enabled |
| No ATC PHY / unknown tunable bucket | DTB | no `atc-phy`/`atcphy` node present |
| USB path as designed | DTB | all three `usb@…` = `dr_mode="host"` + `apple,force-host-mode`; `force-device-mode` fully removed (0 occurrences); six `iommu@…` USB DARTs (`dart,t8110`) all `okay` |
| initramfs is truly read-only in SMOKE | read `scripts/t6040-init-usb-root` | SMOKE branch (no `root=`) mounts only proc/sysfs/devtmpfs, reads `/proc/partitions` + `blkid`, then `exec sh`; never `mount`s a block device |
| Remote visibility | init | reports and an interactive shell run directly over `/dev/ttydc0` (`exec 9<>/dev/ttydc0`), so the run is readable regardless of the kernel's `console=tty0` |
| m1n1 is live-proven | preflight hash | pinned to the zero-PCIe-write upper-guard control from `eed11760`, not a fresh `main` build |
| SMP topology risk contained | preflight + cmdline | `maxcpus=1` prevents starting the unaudited/nonexistent `cpu@10105` (topology reconcile is ticket 034, correctly kept separate) |

## Notes for the run (non-blocking)

- Physical-port mapping is unknown, so all three ports are forced host; whichever
  carries the disk enumerates. VBUS is not manipulated — prefer a self-powered
  enclosure / powered hub for the connected drive. (Ticket 057's ADT port-map
  capture now precedes this and may reduce the DT to one port.)
- This shares the known gadget-era risk (`done/2026-07-11-t6040-usb-gadget-plan.md`):
  a port may enumerate once then go deaf without an `atc-phy,t6040` USB2 PHY driver.
  The pass condition (device present ≥10 s + responsive shell) is exactly the test
  for whether host mode survives that; a deaf port is an informative negative, not a
  safety event.
- Stop conditions in the preflight are complete (async SError, watchdog, DART fault,
  DockChannel loss, repeated controller reset, any sign of NVMe probe).

Ready for CJ approval once re-proposed with final (possibly single-port) hashes.
Sol (`codex`) drives; this reviewer (`claude`) does not contend for the rig on
this experiment.
