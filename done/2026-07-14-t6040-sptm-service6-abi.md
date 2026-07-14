# T6040 SPTM service-6 ABI + GENTER entry-state decode (2026-07-14)

Ticket 007 (offline, P0, storage critical path). Static decode of the Apple
GENTER/SPTM guarded-call ABI that `AppleANS2CGv2Controller` uses for protected
NVMe queue ownership, and of the guarded-execution entry state macOS holds
versus what raw m1n1 boot provides. Pure static analysis; no rig, no MMIO, no
storage access.

## Result

The service-6 ABI is fully decoded at the **caller/selector** level and the
NVMe operation set is enumerated from named driver symbols. The blocker is
confirmed to be architectural, not ABI knowledge: the GENTER guarded-call gate
requires an initialized GXF/SPTM execution environment that iBoot+SPTM
establish during macOS's secure boot and that raw m1n1 boot never sets up
(`SPRR_CONFIG_EL1=0`, `GXF_CONFIG_EL1=0`, guarded entry/abort sysreg reads
trap). Knowing the ABI byte-for-byte does not let raw boot issue a single
service-6 call. This is the evidence base for the ticket 008 go/no-go.

## Provenance (no Apple binary stored in this repo)

Analyzed the paired-target kernelcache from this machine's active Preboot boot
path, decompressed and disassembled only under the session scratchpad:

- Source: `…/FD6945E6-…/System/Library/Caches/com.apple.kernelcaches/kernelcache`
- IMG4 `krnl`, LZFSE; im4p SHA-256
  `0a680269369757af0bd29caa7b0f71e1191e1658a95c9693ed76d106659c5676`
- Decompressed arm64e Mach-O fileset SHA-256
  `e5513a13779a9498114dc13b5e909d9e9ea171e1539e9cf2f69184eae853ffa1`
- Version: `Darwin Kernel Version 24.6.0: … xnu-11417.140.69.710.16~1/RELEASE_ARM64_T6000`
  (macOS host reports 15.3.2/24D81; the Preboot kernelcache is the newer 24.6.0
  image in the boot path). The earlier SART lifecycle note cited a 26.5.2
  kernelcache; the SPTM/GENTER ABI below is SoC/OS-generic and matches both.
- Tools: `pyimg4` (extract+decompress), `radare2`/`nm` (disasm+symbols),
  cross-checked against `~/Code/linux-build-out/nvme-sptm-stubs.dis`.

The decompressed binary and all disassembly stay in the scratchpad; only this
write-up is committed.

## The GENTER guarded-call selector ABI (confirmed)

Apple GENTER is the single instruction `.inst 0x00201420` (bytes `20 14 20 00`;
the assembler has no mnemonic). It has exactly **6** occurrences in the whole
114 MiB kernelcache, all inside one stripped guarded-call trampoline in
`__TEXT_EXEC` (between `_memcmp` and `_flush_dcache64`), i.e. every guarded
service in the kernel funnels through this one gate.

Selector register: `x16 = op | (service << 32)`. Built as
`mov x16, #op` then `movk x16, #service, lsl #32`. Confirmed both by the kernel
trampoline and by the Linux-side reconstruction `nvme-sptm-stubs.dis`, which
enumerates:

- **service 6, ops 0..8** (the NVMe queue service — the ticket target),
- service 3, ops 0..0xc (a broader enumeration probe), and
- service 0xa, ops 4,5.

Argument registers `x0..x4` carry the per-op payload; `x0` carries the return.
The Linux stub veneers wrap each GENTER in a guard-enter / guard-exit `bl` pair,
mirroring the kernel trampoline's prologue/epilogue.

### The kernel guard wrapper (immediately before each GENTER)

```asm
    mov  x15, #0
    mov  w10, #3
    mrs  x14, s3_6_c15_c8_0     ; guarded-mode status/lock sysreg
    cmp  x14, #0
    b.ne .                      ; spin until the guarded gate is idle (==0)
    .inst 0x00201420            ; GENTER  -> SPTM at guarded level
```

The surrounding trampoline also bumps per-thread reentrancy/preemption counters
via `tpidr_el1` (offsets `0x1a8`→`0x270`/`0x278`, `0x1b0`) and PAC-validates the
stack pointer with `autda`/`xpacd` before entry. The load-bearing precondition
is the `mrs s3_6_c15_c8_0` read returning 0: the CPU must be *able to read* the
guarded-mode sysreg and it must report the gate idle before GENTER is issued.

## Service-6 operation set (NVMe queue ownership)

The op *implementations* live in the SPTM firmware (guarded level), not in the
kernelcache; the kernelcache exposes only the caller side. The NVMe operation
semantics are read directly from `IONVMeFamily` `AppleANS2CGv2Controller`
symbols (primary evidence, this kernelcache):

| Symbol | Role |
|---|---|
| `GetNVMeSPTMProtocolVersion()` | negotiate the SPTM NVMe protocol version |
| `GetNVMeSPTMQueueEntries()` | query SPTM-owned queue-entry limits (reads params `0x1824`/`0x1828`) |
| `SetupAdminQueue()` | register admin SQ/CQ with SPTM |
| `EnableSubmissionQueue(u16)` / `PolledEnableSubmissionQueue` | register/activate an I/O submission queue |
| `EnableCompletionQueue(u16)` / `PolledEnableCompletionQueue` | register/activate an I/O completion queue |
| `EnableAutoQueueManage()` | hand queue management to SPTM/ANS |
| `SetupIOQARegister()` | program the protected I/O-queue-attributes register |
| `NVMeCoastGuardSetTCB(...)` / `NVMeCoastGuardSetTCBEntry(tcb_queue_entry*, AppleNVMeRequest*)` | per-command TCB (translation-control-block) authorization |

`SetupAdminQueue` is fully vtable/PAC-dispatched (`blraa` through the ANS2
provider object), so the individual op numbers for the enable/query paths are
resolved inside stripped kernel locals reached via `_pmap_iommu_ioctl` and are
not byte-proven from the caller alone.

### service-6 op → operation map

Confidence is marked explicitly.

| op | Operation | Confidence / evidence |
|---:|---|---|
| 0 | controller/queue-context initialization | **confirmed** — prior live test issued op 0 first; stub table |
| 1 | TCB authorization | **confirmed** — prior finding (`NVMeCoastGuardSetTCB`); stub table |
| 2 | (queue/context op) | slot exists (stub); operation inferred |
| 3 | (queue/context op) | slot exists (stub); operation inferred |
| 4 | admin queue registration | **confirmed** — args below; prior live test |
| 5 | I/O submission-queue registration | slot exists; maps to `EnableSubmissionQueue` (inferred) |
| 6 | I/O completion-queue registration | slot exists; maps to `EnableCompletionQueue` (inferred) |
| 7 | auto-queue-manage / IOQA program | slot exists; maps to `EnableAutoQueueManage`/`SetupIOQARegister` (inferred) |
| 8 | teardown / final activation | slot exists; operation inferred |

Only the numeric assignments for ops 0, 1 and 4 are proven; ops 2,3,5,6,7,8 are
present in the selector space (stub enumeration) and are matched to the
remaining named NVMe operations by elimination, not by byte-level proof. Do not
treat the ops 2/3/5/6/7/8 rows as an exact contract.

### op 4 argument contract (confirmed)

From the reproduced sequence in `patches/t6040-nvme-sptm-debug.patch`, admin
setup is op 0 (no args) followed by op 4:

```
x16 = (6 << 32) | 4
x0  = admin SQ physical address (ASQ PA)
x1  = admin SQ depth - 1
x2  = admin CQ physical address (ACQ PA)
x3  = admin CQ depth - 1
x4  = 0
```

## GENTER entry state: macOS vs raw m1n1 boot (the crux)

macOS reaches the guard wrapper with GXF fully live: iBoot loads and starts the
SPTM firmware at the guarded level, and the guarded-execution config
(`GXF_CONFIG_EL1`, the GENTER entry vector, `SPRR_CONFIG_EL1`) is programmed
before the XNU kernel runs. The `mrs s3_6_c15_c8_0` read then succeeds and
GENTER traps *into the SPTM guarded vector*, which services the request and
`GEXIT`s back.

Raw m1n1 boot provides none of this. The read-only m1n1 snapshot taken before
the prior Linux attempt (`logs/t6040-console-20260714-nvme-sptm.log`) is:

```
SPRR_CONFIG_EL1 = 0x0
GXF_CONFIG_EL1  = 0x0
GXF_STATUS_EL1  = 0x0
GXF_ENTER_EL1   = SYNC exception   (reading the guarded entry sysreg traps)
GXF_ABORT_EL1   = SYNC exception
```

GXF is disabled and its entry vector is unconfigured. With `GXF_CONFIG_EL1=0`
there is no guarded vector for GENTER to dispatch to; the prior live attempt
confirmed the failure mode — the CPU entered `.inst 0x00201420` and never
returned (no `GEXIT`, no exception delivered to Linux), and the watchdog
recovered the machine. So a raw-boot GENTER neither dispatches to SPTM nor
faults cleanly; it wedges.

The gap is therefore not a missing register write Linux can add. It is the
entire SPTM guarded-execution bring-up: loading the SPTM monitor image, entering
GL2/guarded state, and programming `GXF_CONFIG_EL1` + the GENTER entry vector —
work owned by iBoot/SPTM during Apple secure boot, which m1n1's minimal raw boot
deliberately does not perform.

## Implications (feeds ticket 008 go/no-go)

- The service-6 ABI is understood well enough to *reproduce* macOS's exact
  admin-queue call; that was already tried and hung, so the ABI was never the
  missing piece.
- Direct main-BAR / secure-BAR queue programming remains faulting and is not a
  substitute (prior finding): the T8140 controller enforces the SPTM path.
- Storage under raw boot requires one of: (a) m1n1/Linux gaining a documented
  SPTM loader transition into guarded state (large, and SPTM is signed/locked),
  or (b) upstream M4 SPTM support. Neither is a local register tweak.
- Everything here is static. No admin command, Identify, namespace read, mount,
  or storage write occurred, and none is justified by this decode.

## Reproduce

```sh
KC=".../Preboot/FD6945E6-.../com.apple.kernelcaches/kernelcache"
pyimg4 img4 extract -i "$KC" -p kc.im4p
pyimg4 im4p extract -i kc.im4p -o kc.raw          # LZFSE -> arm64e fileset
nm kc.raw | grep AppleANS2CGv2Controller          # NVMe SPTM op inventory
# GENTER sites: search kc.raw for bytes 20 14 20 00 (6 hits, all one trampoline)
```
