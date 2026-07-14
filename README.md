# Project Wallace

Mainline Linux on a MacBook Pro 14" M4 Pro (t6040 "Brava Chop", Mac16,8 / J614s). It boots. BusyBox userspace, working internal keyboard, and a fully remote dev loop over a single USB-C cable: reboot, chainload, boot, interactive shell, all from the host, no fingers on the power button.

This repo is the umbrella. The code lives in four sibling repos and the knowledge kept getting smeared across them so everything that guides the work now lives here: plans, scripts, kernel patches, post-mortems.

## Status (2026-07-14)

Works: raw boot via m1n1 (kmutil raw enrollment, SPTM allows nothing else), all 14 cores in the proxy, BusyBox shell on an Asahi-based kernel (`asahi-wip` plus the t6040 patch stack), internal keyboard, watchdog handover, fbcon on the panel, and a two-way serial console over DebugUSB (`/dev/ttydc0`).

pmgr, the previous blocker, is solved. The full 214-domain topology boots to BusyBox 3/3 with a minimal T6041 quirk: preserve firmware-active domains, disable `disp_cpu`, and skip auto-enable on the two `dispext*_cpu` domains. Every other exclusion we'd been carrying turned out to be unnecessary.

It's a clean two-patch series now, checkpatch and binding schemas both pass; upstreaming is next.

**Internal NVMe** is a no-go for the foreseeable future. The T8140 controller routes every queue operation through Apple's signed SPTM, and raw boot has no path into that guarded state. We decoded the complete GENTER service-6 ABI from the paired kernelcache, so we know exactly what to call; the machine simply refuses the call from anything outside Apple's own boot chain, and the SPTM service-6 ABI is not documented anywhere. The only path to a usable machine is USB-attached root, which is now fully working.

**PCIe**, which carries WiFi/BT and the SD reader, runs Apple's init sequence cleanly through operation 114 and stalls on 115, the first PHY-IP PLL read. Route-finding for the missing aperture precondition continues offline. The paired BCM4388 firmware is already extracted, waiting for the link to come up.

Along the way I spent a day chasing an SError that turned out to be m1n1's own log ring sitting flush against top-of-RAM. The PCIe writes were innocent the whole time.

**Console**: M4 raw-boot has no serial port, no hypervisor tricks (SPTM killed those), and the SBU pins are a confirmed dead end on ACE3. The one path is DebugUSB/KIS through the DFU port. This on the other hand works sorta-nicely.

Linux still polls that DockChannel FIFO every 5 ms. The corrected RX BIT(1) interrupt diagnostic ran clean and answered the wrong question: injected bytes never even reached the AP-side FIFO in the IRQ-mode build, so interrupt delivery has still never been exercised. Polling stays until the build delta between the two IRQ-mode runs is understood.

The blow-by-blow lives in [DEVLOG.md](docs/DEVLOG.md), and the current plan of attack is [NEXT_STEPS.md](docs/NEXT_STEPS.md).

## The repos

| Path | What |
|---|---|
| `~/Code/wallace` | this repo: docs, `scripts/`, `patches/`, `dts/`, `done/` |
| `~/Code/m1n1` | m1n1 fork (bootloader + proxyclient); safety rules live in its `AGENTS.md` |
| `~/Code/m1n1-clean` | worktree of branch `t6040-bringup`, the curated upstream-shaped commit series |
| `~/Code/linux` | `damsleth/linux` fork, branch `wallace/t6040-bringup`, based on AsahiLinux `asahi-wip`; t6040 DTs live here |
| `~/Code/linux-build-out` | build artifacts, mounted as `/out` in the build container |
| `~/Code/macvdmtool` | patched fork: DebugUSB entry + remote reboot |
| `~/Code/kisd` | AsahiLinux kisd, bridges DebugUSB to a pty on the host |

## The loop

```sh
bash scripts/t6040-debugusb-console.sh reboot   # reboot into m1n1, drain console, attach kisd -> /tmp/m1n1
bash scripts/t6040-boot-dcuart.sh               # chainload m1n1 + boot Linux to a shell on /dev/ttydc0
printf 'uname -a\n' > /tmp/m1n1                 # type into the running machine
tail -f ~/Code/linux-build-out/dcuart-console.log
```

Kernel rebuild (arm64-native in a podman container, because macOS's case-insensitive filesystem corrupts a kernel tree in about four files):

```sh
cp scripts/t6040-kbuild.sh patches/*.patch ~/Code/linux-build-out/
podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
    bash /out/t6040-kbuild.sh image
```

Before touching any of this, read the pty-discipline rules in [DEVLOG.md](docs/DEVLOG.md). The link looks completely dead if you handle the pty wrong, and we burned an hour learning that.

## Reading order

1. [AGENTS.md](AGENTS.md), the map (repos, roles, hard rules)
2. [NEXT_STEPS.md](docs/NEXT_STEPS.md), the work queue
3. [DEVLOG.md](docs/DEVLOG.md), recipes, solved blockers, dead ends
4. [ROADMAP.md](docs/ROADMAP.md), stages A through H, from first light to daily driver

`done/` holds the finished per-topic plans and session write-ups. They're kept because the dead ends are half the value: SBU serial, RAM-dump post-mortems, and per-domain pmgr bisection are all documented graves, so nobody digs them up twice.
