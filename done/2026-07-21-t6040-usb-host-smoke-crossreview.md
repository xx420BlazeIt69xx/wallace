# T6040 one-port USB2-host smoke cross-review (2026-07-21)

Reviewer: `usb_smoke_cross_review` (independent agent)

Verdict: **PASS for both port-specific artifact sets, conditional on selecting
and pinning exactly one physical-drive port before CJ approval.**

## Verified artifacts

| Physical drive port | DTB | SHA-256 |
|---|---|---|
| left-front | `t6040-j614s-dcuart-usb-host-left-front.dtb` | `49851557db17448a72fbc99d4274a6688bf1cd2a82a04a4f1ac1756f545212d5` |
| right | `t6040-j614s-dcuart-usb-host-right.dtb` | `429440823f833273a44ab7528cf05c1e782d16f2cc21b532a2308c77e1d6f2d7` |

Both port-specific six-file manifests pass. The kernel, m1n1, initramfs,
System.map, and config hashes match the preflight. The old generic all-port
manifest and DTB are not eligible for a live boot.

## Decompiled-DTB checks

- Left-front enables only `usb-drd1` at `0x38a280000` and its DARTs at
  `0x38af00000`/`0x38af80000`.
- Right enables only `usb-drd2` at `0x392280000` and its DARTs at
  `0x392f00000`/`0x392f80000`.
- Each DTB contains exactly one enabled host controller and one
  `apple,force-host-mode` property.
- `usb-drd0`/left-back and all unused USB/DART groups remain disabled.
- No ATC PHY is enabled. ANS, SART, and internal NVMe remain disabled.

The independent ADT parse also confirms
`usb-drd0/1/2 = left-back/left-front/right` and the raw-capture hash
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.

## Runtime-safety checks and caveats

The initramfs contains no kernel modules; its smoke path mounts only proc,
sysfs, and devtmpfs and does not mount a block device. NVMe is modular and its
module is absent. No PMU/SPMI/charger/NVRAM path is introduced. The selected
USB devices use their existing ADT-derived PMGR power domain, which remains
within the CJ approval gate.

Before approval, replace the preflight's `CHOSEN` placeholder with exactly the
DTB matching the attached drive and use only its matching manifest. Keep the
DebugUSB tether on left-back. Because there is no ATC PHY or explicit VBUS
control, a powered hub or self-powered enclosure is preferred and enumeration
remains experimental.
