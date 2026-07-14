# T6040 (M4 Pro, Mac16,8 / J614s) — roadmap: first light → full Linux desktop

End-goal: a bootable Linux distro on this MacBook Pro 14" M4 Pro with GPU accel,
WiFi, Bluetooth, keyboard/trackpad, audio, webcam, power management — daily-driver
comfort comparable to macOS.

Written 2026-07-10, last updated **2026-07-14** (PCIe map and Stage E image).
Companion docs: `NEXT_STEPS.md` (immediate work), `DEVLOG.md`
(operational reference + solved blockers), `t6040-dt-checklist.md` (Stage C
reference). All finished per-topic plans/write-ups archived in `done/`.
Unposted #asahi-dev drafts awaiting review: `done/2026-07-10-t6040-smp-writeup.md`,
`done/2026-07-10-t6040-cpufreq-writeup.md`.

## Where we are

**Linux reaches userspace on bare metal (2026-07-11).** Mainline 7.2-rc2 plus
the local bring-up patch series boots to a BusyBox shell on the full 214-domain
PMGR DT (maxcpus=1, idle=nop), reproducibly. The internal keyboard works there
(dockchannel-HID,
2026-07-11); the Linux watchdog takes over m1n1's (shell persists); the
framebuffer (simpledrm+fbcon) is the early console.

**Fully remote dev loop (2026-07-12).** Two-way m1n1 proxy AND a two-way Linux
shell (`/dev/ttydc0`, poll-mode dockchannel driver — the ADT's AIC line never
fires on this die) over a single DebugUSB/KIS cable in the DFU port, plus
remote reboot via `macvdmtool`: reboot → chainload → boot → interactive shell
with zero physical access. SBU analog serial was proven a dead end on ACE3.

**Stage A complete 2026-07-10** — proxy solid, 14/14 cores (4E+5P+5P), MPIDR
map, execute-and-return, broken_wfi handled (WFE park), ~10 s chainload loop.

**Stage B effectively complete 2026-07-10** — cpufreq minimal (APSC/pstate;
throttle offsets deferred, need RE), MCC t6041 Ph1+2 (TZ offset + cache-enable
still open), PCIe register map plus clock/PLL targets resolved (first live boot
reached the clock-tunable boundary; bounded trace follow-up gated), ATC/USB DART audited
(DART done, PHY tunables deferred → USB2 fallback), kboot FDT display carveout
fixed, dapf gate + watchdog arm added for M4.

### Current working / not-working snapshot

| Works | Not yet |
|---|---|
| BusyBox userspace; full PMGR with property-free T6041 quirk, reproducible | PMGR draft review/submission (split, checkpatch/schema-clean; NEXT_STEPS #2) |
| Internal keyboard at the shell; trackpad registers + validated firmware-loader path | Target ESP's paired trackpad blob; PMU-backed reset remains forbidden; maxcpus>1/idle states |
| Two-way Linux shell + m1n1 proxy over one DebugUSB cable; remote reboot | Printk over ttydc needs a separate polled/atomic TX path; current TTY queue is not console-safe |
| Linux apple_wdt; fbcon early console | NVMe rootfs (power/SART/ANS work; queue and per-command TCB setup require unavailable raw-boot SPTM entry) |
| Kernel build env (podman, arm64-native) with patch pipeline | USB gadget console (parked: EP0 dies post-enumeration) |
| SMP/cpufreq/MCC groundwork; PCIe host+wireless DT and drivers build | cpufreq throttles, gated PCIe link-up test, wireless firmware, USB3/TB PHY tunables |

**Upstreaming pending**: SMP/broken_wfi/MPIDR + cpufreq drafts (in `done/`);
dockchannel-uart dead-IRQ finding + poll-mode patch to the dockchannel-branch
authors; curated code-only branch `t6040-bringup` tracks main's src/.

One structural constraint colors everything below: **M4 = raw boot only** (SPTM
owns the mach-o path). Apple-private sysregs are locked. Linux itself doesn't
care (it runs at EL2/EL1 normally), but: no hypervisor tracing of macOS drivers
on this machine — the classic Asahi reverse-engineering tool (`hv` + tracers) is
crippled on M4. Reverse engineering of new hardware blocks largely has to happen
on M1/M2/M3 machines upstream, or via static ADT/firmware analysis. This is the
single biggest reason most of Stages E–G are "track upstream" rather than "build
it here".

## Stage map

```
A. Proxy solid ──► B. m1n1 Linux-boot ──► C. Kernel DT + boot ──► D. Storage/USB/HID/console
                                                                        │
        ┌───────────────────────────────────────────────────────────────┤
        ▼                          ▼                        ▼           ▼
E. WiFi + Bluetooth        F. GPU (long pole)        G. Audio/ISP/PM   H. Distro integration
```

A→D are sequential. E/F/G parallelize after D. H wraps it all.

---

## Stage A — proxy solid, all cores ✅ COMPLETE (2026-07-10)

*Was `done/t6040-bringup-plan.md` phases 2–4. Took days, as scoped.*

- [x] Second machine + `shell.py` → proxy prompt (M1 host over USB; no PR #616 needed)
- [x] `smp.start_secondaries()` — `CPU_START_OFF_T6031` 0x88000 (src/smp.c:296)
      **validated correct**; all 14 cores up. Plus execute-and-return + MPIDR map.
- [x] `chainload.py -r build/m1n1.bin` reliable → ~10-second dev loop, kmutil retired
      **(done 2026-07-10, build chain fixed)**
- [ ] Upstream: confirmed constants, features_m4/broken_wfi notes, raw-boot doc note
      *(residual — draft ready in `2026-07-10-t6040-smp-writeup.md`)*

**Exit:** ✅ proxy stable across reboots, 14/14 cores. (chainload dev loop + upstream
carry forward as small residuals; neither blocks Stage B.)

## Stage B — m1n1 grows Linux-boot support for T6040

*What `kboot` needs before it can hand a kernel a usable machine. This is the
M3 template (commits 83364d0→5393f41) replayed on T6040. Weeks. All of it is
doable solo with the proxy + ADT dumps; this is the highest-leverage local work.*

1. ✅ **cpufreq** (`src/cpufreq.c`) — **DONE (minimal) 2026-07-10.** T6040 reuses
   `t6031_clusters`; pstate/APSC working. Throttle features deferred (t6030 offsets
   SError on T6040 P-clusters → need RE). See `2026-07-10-t6040-cpufreq-plan.md`.
2. **MCC** (`src/mcc.c`) — **Phases 1+2 DONE (2026-07-10).** `mcc_init_t6041()`
   added: t6031 reuse mis-parsed the ADT (AMCCs at `reg[12..15]` per `amcc-reg-idx`/
   `amcc-count`, no `plane-count-per-amcc`). Phase 2 hardware-RE'd the SLC: 1 plane
   per AMCC, status = 0x00010101 (T6031 decode wrong) — both encoded as `T6041_*`
   constants. Boots clean, no MMIO at init. **Open (Stage C):** TZ/carveout offset
   (t603x regs read 0 despite real carveouts) + the gated `mcc_enable_cache()`
   write. Detailed in `2026-07-10-t6040-mcc-plan.md`. Needed for memory BW / DCP.
3. **PCIe** (`src/pcie.c` + tunables) — **HOST-SIDE COMPLETE; LIVE GATED
   (2026-07-14).** Added
   `regs_t6040` + `apcie,t6040` dispatch branch. ADT-verified against live
   `/arm-io/apcie0`: 35 regs, #ports=4, shared block = reg[0..6] then 4×7 port
   regs ⇒ `shared_reg_count=7` (the one delta vs t6031; 8 would fail the
   even-divide check). Static analysis of `AppleT6040PCIe::start()` proves the
   two new clock groups target reg[5] (CIO3 PLL) and reg[6] (PCIe clkgen); m1n1
   now applies both and reuses the T6031/T8122 init path. The matching
   PCIe/DART/BCM4388/GL9755 Linux DT and driver image build cleanly. The first
   live attempt reached `No common tunables` and then hung; DebugUSB warm-reboot
   recovered the proxy. A 105-write clock-only trace build is ready and gated
   on explicit approval. Detailed in
   `2026-07-14-t6040-wireless-pcie-map.md`. WiFi/BT prerequisite.
4. **ATC/USB tunables + DART config** — **AUDITED 2026-07-10 (mostly verify+defer).**
   All kboot-only, FDT-only (safe). **DART = done** (t6040 DARTs are `dart,t8110`,
   fully supported). **ACIO USB4 rc+pcie_adapter = works as-is** (prop names match).
   **ATC PHY tunables = blocked** on the t6040 PHY reg-bucket offsets (FDT bucket
   names are stable; only per-bucket reg_offset/size is the unknown — mustn't
   invent). Graceful USB2-only fallback means this does NOT block Stage C; USB3/TB
   is a Stage D comfort. NHI/apciec (Thunderbolt) name-mapping also deferred.
   Watch `upstream/atcphy-new-tunables`. Detailed in
   `2026-07-10-t6040-atc-usb-dart-plan.md`.
5. **kboot FDT init** (`src/kboot.c` and friends) — **AUDITED + display FIXED
   2026-07-10.** kboot-only, FDT-only (safe), Stage-C-coupled (patches a kernel DT
   that doesn't exist yet). Generic parts already work for t6040: spin-table/
   CPU-release (`dt_set_cpus`, SMP done), DART (t8110), ACIO. **Fixed:**
   `dt_set_display` now has a t6040 branch — was hitting "unknown compatible, skip",
   now reuses the t602x carveout scheme (region-id 49/50/57/94/95/157 verified on
   the live carveout map) + dcpext firmware. **Deferred:** compat fixup (speculative
   until a real t6040 DT exists), GPU carveout (Stage F), dcpext data-region
   validation, ISP/SEP/SMC (verify at Stage C). Detailed in
   `2026-07-10-t6040-kboot-fdt-plan.md`.
6. **Python side** (`proxyclient/m1n1/`) — T6040 chip knowledge for the tools
   used to dump/verify all of the above.

**Exit:** m1n1 boots a kernel image with a correct, complete FDT; kernel gets to
early console. (Testable incrementally against Stage C.)

## Stage C — kernel devicetree + core boot (Asahi kernel tree)

*Target: linux-asahi boots to a shell on this machine. Weeks, parallel with B.*

- **Device trees:** **FULL 214-DOMAIN PMGR TO USERSPACE (2026-07-12, temporary
  policy).** `t6040.dtsi`
  + `t6040-j614s*.dts` + generated `t6040-pmgr.dtsi` in `~/code/linux`
  (templated from t8132/t6050, ADT-verified). The 2026-07-10 async-L2C-SError
  handoff blocker was the m1n1 dapf init (all t6040 dapf entries trap; gated in
  `src/dapf.c`). Board variants: `-kbd` (keyboard, known-good) and `-dcuart`
  (keyboard + DockChannel shell, preserved at `~/Code/wallace/dts/`). **Remaining:
  full-pmgr legacy policy hangs pre-console, but the exact deterministic minimum
  (preserve active, disable `disp_cpu`, skip auto-enable only for
  `dispext0_cpu` and `dispext1_cpu`) boots 3/3. Both CPU skips are necessary;
  the former `sys`, `fe`, and ANE restrictions are not.
  The live-tested T6041-compatible quirk now carries that policy without custom
  DT booleans; review/upstream submission is the remaining Stage C PMGR work**;
  see NEXT_STEPS #2 and DEVLOG's PMGR section.
- **AIC3:** **works** — yuka's branch has `apple,t8122-aic3` support; boots and
  delivers interrupts (keyboard mailbox IRQs verified live). Two locked-sysreg
  writes in `aic_init_cpu` must be skipped on M4 raw-boot (flokli patch).
- **Core platform drivers** (mostly compat-string + minor deltas on existing
  Asahi drivers): UART, watchdog, PMGR power domains, pinctrl/GPIO, I2C/SPI,
  mailbox/RTKit (new firmware version strings for 26.x!), DART t8110, cpufreq
  (`apple,cluster-cpufreq`), SMC, SPMI/PMU.
- **RTKit firmware versioning:** every coprocessor (NVMe/ANS, SMC, DCP, ISP…)
  ships firmware from the macOS 26.x install; Asahi drivers whitelist known
  ABI versions. Expect a steady trickle of "add fw 26.x compat" patches.

**Exit:** linux-asahi + our DT boots to initramfs shell over USB gadget/serial,
all 14 cores online, cpufreq working.
**Status 2026-07-12:** initramfs shell reached (maxcpus=1) with a real serial
console over DebugUSB/dockchannel; remaining for exit: full pmgr, then
maxcpus>1 + cpufreq DT wiring.

## Stage D — storage, USB, HID, display console (usable machine)

*The "it's a real computer now" stage. Weeks.*

- **NVMe** (apple-nvme + SART + ANS RTKit): internal SSD. PCIe parents can be
  forced actual-on; CoastGuard/SART activation, RTKit buffers, ANS boot, and
  boot status all succeed. T8140 then rejects direct legacy and standard NVMe
  queue-register programming. macOS uses guarded SPTM service 6 for queue and
  per-command TCB authorization. Its ABI is decoded, but raw boot has
  SPRR/GXF disabled and the exact GENTER call hangs. iBoot's queue buffers are
  ordinary, unreserved RAM and the macOS path performs per-command TCB
  authorization, so preserving only the firmware ASQ/ACQ is not a complete
  Linux design. Do not repeat direct register or GENTER attempts unchanged
  (NEXT_STEPS #3).
- **USB** (dwc3 + ATC PHY): external keyboard/disk/ethernet from day one; also
  the USB-gadget console m1n1 already proves works.
- **Internal keyboard + trackpad:** ✅ **keyboard DONE early (2026-07-11)** via
  dockchannel-HID (three bugs fixed — see DEVLOG); trackpad registers as
  input0. Its missing HIDF loader and retry recovery are fixed; provision the
  paired `tpmtfw-j614s.bin`, then determine whether J614s needs the legacy GPIO
  proxy path (NEXT_STEPS #1).
- **Display:** two steps.
  1. `simpledrm` on the m1n1-provided framebuffer — works immediately, no
     driver; gives a desktop-capable (unaccelerated) console. This alone plus
     NVMe/USB/HID = installable, usable-in-anger machine.
  2. **DCP driver** for real display control (brightness, DPMS, mode switch,
     external DP alt-mode). Firmware-version-locked; M4 + macOS 26.x firmware
     support must exist in the asahi DCP driver — likely upstream-tracking work.
- **SMC:** power button, lid, battery/charger via macsmc — mostly compat work.

**Exit:** boot from internal NVMe to a desktop on simpledrm, working built-in
keyboard/trackpad, battery status. Daily-drivable without GPU/WiFi (USB ethernet).

## Stage E — WiFi + Bluetooth

*Moderate; mostly enablement, not R&E — the drivers exist. Depends on Stage B PCIe.*

- **Mapped and host-built 2026-07-14:** port 0 is BCM4388 WiFi (`14e4:4434`)
  plus Bluetooth (`14e4:5f72`), board module `mriya`; port 1 is the GL9755 SD
  reader. Linux already carries both Broadcom IDs and explicit BCM4388 support.
  The complete PCIe/GPIO/DART child topology is in the separately gated
  `t6040-j614s-dcuart-pcie` DT; see
  `done/2026-07-14-t6040-wireless-pcie-map.md`.
- **Immediate gate:** approve the 105-write m1n1 clock-tunable trace using the
  base Linux DT (no Linux PCIe node). The first opaque attempt stalled after
  `No common tunables`; the new image prints before/after every RMW and stops
  before PHY/ports. Review that result before enabling the full path or Linux
  host node; until link-up succeeds, firmware work cannot be exercised.
- **WiFi:** `brcmfmac` PCIe path; m1n1 already copies the MAC, antenna SKU and
  calibration blob from ADT when `wifi0` is aliased. Firmware still has to be
  extracted from the paired macOS install for board type `apple,mriya`.
- **Bluetooth:** `hci_bcm4377`; m1n1 copies the address and calibration blobs.
  The paired BCM4388 firmware still has to be packaged in the initramfs/rootfs.
- If the chip generation is genuinely new (not just a new ID), this becomes
  upstream-collab work — but Broadcom generations have been incremental so far.

**Exit:** WiFi associates + BT pairs on mainline-asahi drivers with extracted fw.

## Stage F — GPU (the long pole)

*This is the item that decides when "all the comforts" arrives. Not a solo project.*

- M4 GPU is the G15/G16 family (M3 introduced Dynamic Caching — a large
  architectural break from the G13/G14 the shipping drm/asahi driver grew up on).
  Kernel driver (Rust, drm/asahi) + firmware ABI + Mesa compiler (agx) all need
  the M3/M4-generation work that the upstream Asahi team has been driving since
  the M3 bring-up; the 2026-06 progress report explicitly says M4 groundwork is
  being laid.
- Firmware ABI is version-locked per macOS release → our 26.x install needs
  explicit support.
- **Realistic role for this machine:** be the T6040 test mule — provide ADT/fw
  dumps, run bring-up branches, report. Writing a G16 GPU driver from scratch
  here is out of scope; the raw-boot hypervisor limitation (no XNU tracing on
  M4) means even upstream does the RE on other hardware.
- **Until it lands:** simpledrm desktop. KDE on simpledrm at 3024x1964 is
  serviceable; no video decode offload, no games, high CPU for compositing.

**Exit:** drm/asahi + Mesa honeykrisp/agx running the desktop with GL/Vulkan.

## Stage G — comforts: audio, camera, power

- **Speakers/headphones:** macaudio stack (tas2764 amps + cs42l84 jack codec are
  the recurring parts) — needs j614s DT wiring, `speakersafetyd` limits, and an
  **asahi-audio DSP profile measured for this exact chassis** (each model gets
  tuned EQ; 14" M4 Pro won't exist yet). Speaker safety is a hard gate: no
  profile → speakers stay muted. Headphones/USB audio work much earlier.
- **Webcam:** apple-isp driver + m1n1 ISP prealloc (Stage B item) + new sensor/
  firmware handling for the 12MP Center Stage camera. Upstream-tracking.
- **Power management:** s2idle suspend via SMC (works on M1/M2, needs T6040
  validation); `features_m4` sleep_mode currently SLEEP_NONE in m1n1 — deep-WFI/
  cpuidle needs careful enablement under locked sysregs. Battery life tuning
  (devfreq, runtime PM on DARTs/coprocessors) trails everything else.
- **Explicitly never (or SEP-blocked):** Touch ID. **Late/limited:** Thunderbolt
  tunneling (USB3/DP alt-mode work; full TB is still open upstream), video
  decode engines (AVD is M1/M2-era work, M4 unexplored).

## Stage H — distro integration ("bootable Linux distro")

- **asahi-installer:** must learn raw-boot-object enrollment for M4 (it enrolls
  mach-o m1n1 today — that path is *gone* on this machine) + Mac16,8 device
  metadata + firmware extraction for 26.x. This is a real, non-optional work item
  and mostly upstream-installer territory.
- **U-Boot:** T6040 support (usually near-free once m1n1's FDT + dwc3 are right)
  → standard EFI boot flow → GRUB/systemd-boot.
- **Fedora Asahi Remix:** kernel with all of the above, j614s asahi-audio
  profile, mesa builds, calamares/initial-setup — mostly automatic once the
  pieces exist upstream.
- Interim personal path (before official installer support): keep the APFS
  m1n1 volume + kmutil raw enrollment, m1n1 chainloads U-Boot/kernel from the
  existing setup. That's a "my machine boots Linux" milestone long before
  "a distro supports this machine".

## Dependencies & effort summary

| Stage | Blocked by | Who realistically does it | Effort |
|---|---|---|---|
| A proxy/SMP | — | you, now | days |
| B m1n1 kboot | A | you (best solo leverage) | weeks |
| C kernel DT/boot | B partial, AIC3 driver | you + upstream | weeks |
| D NVMe/USB/HID/simpledrm | C | you + upstream compat patches | weeks |
| E WiFi/BT | B (PCIe), D | mostly enablement, you | days–weeks |
| F GPU | upstream M3/M4 GPU program | upstream; you = test mule | months (external) |
| G audio/ISP/PM | D; audio profile needs hw measurement | mixed | weeks–months |
| H installer/distro | all above | upstream + you for j614s bits | weeks (external) |

## Risks (beyond the bring-up plan's table)

| Risk | Mitigation |
|---|---|
| No hypervisor tracing on M4 (SPTM) starves RE for new blocks | Static ADT/fw analysis; lean on upstream's M3 machines where blocks are shared |
| macOS 26.x firmware ABIs unsupported by every RTKit driver | Expect per-driver fw-version patches; keep the m1n1 volume's macOS pinned once things work |
| AIC3 unsupported in kernel | Check asahi tree first — if missing, it's the Stage C critical path; raise on #asahi-dev early |
| GPU timeline entirely external | simpledrm desktop is the honest interim; don't plan around a date |
| Speaker safety profile requires acoustic measurement rig | Use headphones/USB audio until a j614s profile exists upstream |

## Operating principle

Everything in Stages A–B and the DT/enablement halves of C–E is scarce-hardware
work where a T6040 owner adds unique value — do it, upstream it fast, coordinate
on #asahi-dev before writing anything big. Stages F and the deep halves of G–H
are upstream programs — track, test, report, don't fork.
