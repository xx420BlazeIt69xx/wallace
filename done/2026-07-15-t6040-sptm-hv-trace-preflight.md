# SPTM HV genter-trace — rig-experiment preflight & pre-review (2026-07-15)

Preflight for ticket **053** (needs=rig, NOT yet approved), following the project's
offline-preflight → cross-review → maintainer-approve → gated-run pattern (cf. 034→005,
035→006, 044). Objective of the eventual rig run: boot the M4 macOS kernelcache as an m1n1
EL2 HV guest and **read-only trace** its SPTM `genter` calls through NVMe bring-up, to
answer two questions the XNU-shim route (ticket 055) hinges on:

- **Domain provenance** — is a post-`init_xnu_ro_data` EL1 context tagged `XNU_DOMAIN` (the
  go/no-go for driving SPTM from a shimmed Linux)?
- **Live per-op args** — the real x0..x7 for NVMe ops 0..8, to finalize `sptm_nvme_iface.h`
  and cross-check the static handler decode (ticket 051).

## Why this is NOT runnable on the rig today (the prerequisite chain)

Confirmed against `~/Code/m1n1` @ `16b1f61f`:

1. **m1n1 GXF is OFF on the whole M4+ family.** `features_m4` (`src/chickens.c:112`) omits
   `.mmu_sprr` (M1/M2/M3 set it; the `XXX figure out what features are actually available
   on M4` comment sits right above). `features_m4` backs T8132/T6040/T8140/T6050/T6051, so
   `gxf_init()` never runs on the target. Enabling it is an **uncharacterized CPU-feature
   change** → maintainer-gated (m1n1 AGENTS rule 2), and possibly not even the needed
   mechanism (see #2).
2. **HV genter-interposition on M4 is unproven.** To *observe* a guest's SPTM calls, m1n1
   at EL2 must trap or hook the guest's EL1→GL genter path. m1n1's hv has SPRR/GXF handling
   but it is gated on `apple_sysregs_unlocked` — false on raw-boot T6040 (locked sysregs).
   Open question: does a guest genter trap to EL2, or must we trap the guest's MSR writes to
   `GXF_CONFIG_EL1`/`GXF_ENTER_EL1` (HCR_EL2/fine-grained traps) and interpose the entry
   vector? This is the core unknown and the bulk of the work.
3. **The probe is a stub with the wrong ABI.** asahi_neo `scripts/probe_sptm.py` still
   carries the invalidated `x0`-dispatch model; it must be rewritten for the x16 descriptor
   (`domain<<48 | table<<32 | endpoint`) and wired to m1n1's real hv proxyclient API.

## Offline preflight deliverables (ticket 056 — do these before requesting rig time)

1. **m1n1 HV-GXF-on-M4 feasibility note + minimal DRAFT patch** — set `.mmu_sprr` for
   `features_m4`, verify the `gxf_init()`/`supports_gxf()` path is sane on M4, and determine
   whether guest GL transitions are observable from EL2. Draft only; **not flashed** — it is
   the gated change CJ must review (rule 2).
2. **HV genter-interposition design** — resolve #2 above: the exact trap/hook mechanism and
   where the log point sits. Cite the M1/M2 hv SPRR/GXF path as the template.
3. **Probe rewrite** — `probe_sptm` for x16: hook the GXF entry, decode domain/table/endpoint
   + log x0..x7 + guest ELR, emit JSON. Cross-check decoded ops against `sptm_nvme_iface.h`.
4. **Cross-review packet + hashes** — the built m1n1 SHA, the guest KC hash, the exact command
   sequence, and the stop points below.

## Safety envelope for the eventual rig run (053)

- **Read-only trace.** m1n1 issues **no** SPTM calls and **no** MMIO writes; it only logs the
  guest's. Internal SSD is untouched (observe, never write). No SPMI/PMU/NVRAM (rule 1).
- **The GXF-enable is the risky bit.** An uncharacterized `mmu_sprr` flip on M4 could raise an
  async SError (uncatchable by `GUARD.SKIP`) and wedge the proxy → power-cycle. Treat first
  boot as a one-shot, ready to power-cycle; do not retry into a wedge (rule 6).
- **Guest-XNU-under-HV is heavy and has failed before** (asahi_neo's HV-autoboot timed out on
  XNU entry). Expect guest faults; the trace must survive them (log EC/ESR/ELR, stop).
- **Stop points:** (a) guest XNU fails to reach `init_xnu_ro_data` → capture entry fault, stop;
  (b) proxy wedges → documented recovery once, else stop; (c) any SError on the GXF flip →
  power-cycle, stop, report. Hold the rig lease throughout; release with accurate `--state`.

## Approvals required from the maintainer (CJ) before any rig time

1. **`TICKET-APPROVE seq=053`** once the 056 preflight + cross-review packet is ready.
2. **Sign-off on the GXF-enable-on-M4 draft patch** (gated CPU-feature change) — review the
   exact diff before it is ever built into a rig-flashed m1n1.

Until both land, 053 stays unrunnable and this track's progress is the offline 056 work.
No rig was driven to produce this preflight; the lease was checked (FREE) but not taken.
