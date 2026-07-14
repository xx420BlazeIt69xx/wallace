# T6040 USB2 external-root artifact set (2026-07-14)

Ticket 032 (offline, P1, storage track). Reproducible artifact set for booting
Linux with root on an external USB2 disk (ticket 009 design; internal NVMe
SPTM-blocked, ticket 008), built on ticket 031's USB2-host DT candidate. Static
build only; stops before any rig run.

## What this delivers

| Artifact | What | Status |
|---|---|---|
| `patches/t6040-dwc3-apple-force-host.patch` | the enabler: `apple,force-host-mode` | in repo; **applies clean on `t6040-usb-wip`** (verified in the kbuild container) |
| `dts/t6040-j614s-dcuart-usb-host.dts` | USB2 host DT (all 3 ports forced host) | in repo (ticket 031); dtc-clean |
| `scripts/t6040-init-usb-root` | dual-mode init (smoke + root) | in repo |
| `scripts/t6040-kbuild.sh` `USB_HOST=1` block | reproducible kernel config + patch-apply + DTB | in repo |
| kernel `Image-usb-host` / `.dtb` / `initramfs-usb-root.cpio.gz` | built binaries + hashes | **blocked — branch integration (see gate 1)** |

**Build status (2026-07-14):** the `USB_HOST=1` kernel build was attempted in the
warm kbuild container against `BRANCH=t6040-usb-wip`. The force-host patch applied
cleanly (`t6040-dwc3-apple-force-host.patch applied OK`), but the build then
failed applying a *mainline-required* patch — `t6040-pmgr-t6041-quirks.patch`
does not apply to `t6040-usb-wip`'s `pmdomain/apple/pmgr-pwrstate.c`. So
`t6040-usb-wip` is not a clean superset of the mainline bring-up branch: the USB
driver work and the PMGR/other bring-up work sit on divergent branches, and
neither branch alone builds a bootable USB-host image. Producing the binaries is
therefore gated on integrating the dwc3-apple USB work and the mainline bring-up
series onto one branch (gate 1) — a coordination step, not attempted here. Config,
patch, DT, and init are all validated and reproducible; only the final link is
blocked.

## The enabler: apple,force-host-mode

`dwc3-apple` is role-switch driven — on probe it stays in
`DWC3_APPLE_PROBE_PENDING` and only enters host/device mode on a Type-C cable
event. M4 has no AP-visible PD controller to deliver one, so `dr_mode="host"`
alone never brings the port up. The in-tree `apple,force-device-mode` handles
this for gadgets; `patches/t6040-dwc3-apple-force-host.patch` adds the symmetric
`apple,force-host-mode` (forces `dwc3_apple_init(HOST)` at probe) — an exact
structural mirror of the device-mode block.

## Kernel config (in `scripts/t6040-kbuild.sh`, `USB_HOST=1`)

Built-in so root is reachable with no modules: `USB`, `USB_XHCI_HCD`,
`USB_XHCI_PLATFORM`, `USB_DWC3` + `USB_DWC3_HOST` + `USB_DWC3_DUAL_ROLE` +
`USB_DWC3_APPLE`, `APPLE_DART`/`IOMMU_SUPPORT`, `USB_STORAGE`, `USB_UAS`, `SCSI`,
`BLK_DEV_SD`, `EXT4_FS` — on top of the proven DockChannel-console + fbcon base
(`DOCKCHANNEL=1`). No ATC PHY / USB3 / Thunderbolt (deferred; USB2 high-speed
only).

## initramfs init (`scripts/t6040-init-usb-root`)

One init, two modes:
- **SMOKE** (no `root=` resolves): report dwc3/xhci/dart/usb-storage dmesg, USB
  device tree, `/proc/partitions`, `blkid`, over the DockChannel console, then a
  shell. This is the rig smoke test — proves the forced-host port enumerates a
  device and survives past enumeration.
- **ROOT**: `root=PARTUUID=<uuid>` (also `LABEL=`/`UUID=`/`/dev/*`), waits up to
  30 s for the disk, mounts `rootfstype` (default ext4), `switch_root`.
It never mounts an internal device; any failure stops at a diagnostic shell.

## Build recipe (turnkey)

```sh
cp ~/Code/wallace/scripts/t6040-kbuild.sh ~/Code/wallace/patches/*.patch ~/Code/linux-build-out/
cp ~/Code/wallace/dts/t6040-j614s-dcuart-usb-host.dts ~/Code/linux/arch/arm64/boot/dts/apple/
podman exec -e DOCKCHANNEL=1 -e USB_HOST=1 -e BRANCH=t6040-usb-wip \
    -e BUILD_DIR=/build/linux-usb-host2 kbuild bash /out/t6040-kbuild.sh image
# initramfs:
OUT=~/Code/linux-build-out INIT_SOURCE=~/Code/wallace/scripts/t6040-init-usb-root \
    DEST=~/Code/linux-build-out/initramfs-usb-root.cpio.gz \
    bash ~/Code/wallace/scripts/t6040-make-initramfs.sh
```

Note the **branch**: the dwc3-apple USB driver work (force-{device,host}-mode)
lives on `t6040-usb-wip`, not the mainline `feature/m4-m5-minimal-device-trees`
the harness builds by default — `BRANCH=t6040-usb-wip` is required (kbuild.sh now
honours the override). Integrating that driver work into the mainline bring-up
branch is a separate coordination step (see gates).

## External rootfs recipe (populate at deploy)

Not a git artifact (multi-GB). Recipe:
- Partition the external USB disk GPT, one ext4 root partition with a stable
  `LABEL=t6040root` (and note its `PARTUUID`).
- Populate a base arm64 userland (e.g. a minimal Debian/Alpine arm64 rootfs) with
  `/sbin/init`; add the Asahi firmware corpus (tickets 014/016/030) for WiFi/BT
  etc. Boot-critical path needs no firmware.
- Kernel modules: the USB/storage/ext4 stack is built-in, so none are required to
  reach root; install the full `modules/` tree into the rootfs for everything
  else.

## Bootargs

```
console=ttydc0 maxcpus=1 idle=nop root=PARTUUID=<uuid> rootfstype=ext4 rootwait
```

(`maxcpus=1 idle=nop` per the proven M4 bring-up; `console=ttydc0` for remote
console; `rootwait` plus the init's own 30 s wait covers USB enumeration.)

## Read-only first-boot procedure (stops before rig run)

1. Boot the SMOKE artifact set first (no `root=`): confirm on the DockChannel
   console that a USB device enumerates on a forced-host port and that
   `/proc/partitions` shows a `sd*` disk that stays present for >10 s (rules out
   the gadget-style post-enumeration deafness). Record which physical port worked.
2. Only if smoke passes: populate the external rootfs, then boot the ROOT
   artifact set with `root=PARTUUID=…`. Verify `switch_root` reaches the external
   userland's shell.
3. The internal SSD is never read or written by Linux at any step.

## Gates (why this stops here)

1. **Build/branch integration.** USB host needs the `t6040-usb-wip` dwc3-apple
   work; building requires `BRANCH=t6040-usb-wip`. Merging that driver support
   into the mainline branch is a maintainer/coordination decision, not done here.
2. **Rig smoke test before the rootfs.** The parked gadget effort enumerated once
   then went deaf (suspected missing `atc-phy,t6040` USB2 PHY driver / wrong
   dwc3-apple wrapper offsets; `done/2026-07-11-t6040-usb-gadget-plan.md`). Host
   mode may share that failure. So the SMOKE test must pass on the rig before an
   external rootfs is populated — do not invest in the rootfs on the assumption
   host works. This is the next rig experiment to propose (needs the lease + CJ).

No rig, no MMIO, no storage access performed.
