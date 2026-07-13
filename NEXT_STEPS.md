# t6040 Linux bring-up — NEXT STEPS

Handoff state (2026-07-13): mainline Linux boots to a BusyBox shell on the
M4 Pro with working internal keyboard, watchdog, and a **fully remote dev
loop** — two-way m1n1 proxy AND Linux shell (`/dev/ttydc0`) over one DebugUSB
cable; reboot via `macvdmtool`. No screen-reading or physical access needed.
Operational details, recipes, and history: `DEVLOG.md`. Long-term: `roadmap.md`.
Read the DebugUSB link rules in DEVLOG before touching the rig.

## 1. Provision and test the J614s trackpad firmware
`event0` is Apple DockChannel Multi-touch and `event1` is the keyboard. The
transport's missing firmware loader and stuck-start error path are fixed and
live-tested in kernel build #12: repeated opens now independently request
`apple/tpmtfw-j614s.bin` and return `-ENOENT`, with no invalid resets or stale
`-EINPROGRESS`. Retrieve the paired HIDF blob from this target's Asahi ESP at
`vendorfw/apple/tpmtfw-j614s.bin`, or process its
`asahi/all_firmware.tar.gz` with `asahi-fwextract`, then rebuild with
`TRACKPAD_FIRMWARE=/path/to/tpmtfw-j614s.bin`, and retest motion. If MTP then
requests its reset GPIO, stop: the now-derived `gp1c` function resolves through
the ADT's `smc-pmu` node, and PMU writes are forbidden by the project rules.
No tactile click is expected yet (the haptic actuator is a separate interface).
Full finding:
`done/2026-07-12-t6040-trackpad-firmware.md`.

## 2. Review and upstream the proven T6041 PMGR quirk
The full 214-domain topology now boots to BusyBox **3/3** with the exact minimal
temporary policy: preserve firmware-active domains, disable only `disp_cpu`,
and skip auto-enable only on `dispext0_cpu` and `dispext1_cpu`. Both CPU skips
are individually necessary at bank granularity; the `sys`, `fe`, and five old
ANE exclusions are unnecessary. Legacy raw fails 3/3. Full matrix and hashes:
`done/2026-07-12-t6040-pmgr-matrix.md`.

The supported shape is now implemented and live-tested in build #14. The
two-patch draft starts with `patches/t6040-pmgr-t6041-bindings.patch`, then
`patches/t6040-pmgr-t6041-quirks.patch` selects preserve-active and the two CPU
auto-enable exceptions from `apple,t6041-pmgr-pwrstate`; Linux `37339d595765`
removes the experiment-only properties from the standard DT. The series passes
checkpatch and both binding schemas validate. No further policy bisection is
needed.

Next, in leverage order:
1. Ask flokli for the J773s PMGR policy (draft only here; maintainer sends).
2. If pre-userspace attribution becomes necessary, first add a bounded
   polled/atomic TX primitive to the DockChannel mailbox. Do not register the
   current `ttydc` kfifo/workqueue path as a printk console: it is not safe in
   atomic or panic context and can recurse through its own error printk.

Done this session: raw determinism, requested core-infra and PMGR1 isolations,
live ADT regeneration, `no_ps` parent filtering, and safe always-on generation
(no policy by default; explicit legacy flag only).

## 3. Approve the CoastGuard SART power write, then resume NVMe
The approved first probe did not reach NVMe enumeration. Both the built-in
candidate and a staged candidate with `nvme-apple` still unloaded reset before
userspace. A cumulative DT bisection proved that the ASC mailbox alone boots,
while adding SART (with NVMe disabled) reproduces the reset. No disk command
was issued and no namespace was mounted or written.

Read-only ADT inspection then found the missing hardware contract:
`/arm-io/sart-ans` is a power-managed CoastGuard SART. Its control is ADT reg 2
plus `sart-power-reg-offset = 0x13e8`, exactly `0x20dcc13e8`. Static analysis of
the paired Apple kernel established the protocol: while holding a lock and
reference count, write `0`, delay 100 us, and retry until the register reads
`0` to activate; on the last release write `1`, delay 100 us, and retry until
it reads `1`. The existing Linux fallback read inactive SART entries and caused
the reset.

Draft bindings and driver support are in
`patches/t8140-sart-power-bindings.patch` and
`patches/t8140-sart-power-managed.patch`; both compile, the focused schema
passes, and checkpatch is clean. A staged SART-only retry artifact is built,
but **must not be booted until the maintainer separately approves the newly
discovered writes to `0x20dcc13e8` with values `0` and `1`**. The earlier NVMe
approval did not describe this register.

After approval, proceed cumulatively: SART-only DT first; then full DT with the
NVMe module still unloaded; only then load `nvme-core.ko` and `nvme-apple.ko`
and run the read-only enumeration transcript in
`done/2026-07-13-t6040-nvme-map.md`. Never mount, repair, format, flush, or write
the namespace during this probe.

## 4. Upstream / share
- Post the drafted writeups: `done/2026-07-10-t6040-smp-writeup.md`,
  `done/2026-07-10-t6040-cpufreq-writeup.md` (#asahi-dev).
- Keep the curated code-only branch `t6040-bringup` (worktree
  `~/Code/m1n1-clean`) in sync with any new src/ changes on main.
- Report the dockchannel-uart dead-IRQ finding + poll-mode patch to the
  dockchannel-branch authors (yuka / Michael Reeves) — t8140 may differ.

## Parked (revisit after pmgr)
- USB gadget console → gadget-Ethernet + SSH (EP0 dies post-enumeration;
  `done/2026-07-11-t6040-usb-gadget-plan.md`).
- cpufreq throttle offsets (t6030 offsets SError on t6040 P-clusters; needs RE
  or #asahi-dev answer).
- ATC PHY tunables (USB3/TB) — blocked on t6040 PHY reg-bucket offsets;
  USB2-only fallback is fine for now.
