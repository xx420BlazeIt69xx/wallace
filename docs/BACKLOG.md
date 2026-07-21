# BACKLOG — strategy & priorities

This is the **map**, not the ticket list. The actionable work lives in tickets:

- **`tickets/`** — one git-tracked JSON file per ticket, offline tasks and rig
  experiments alike. Managed only through the CLI (don't hand-edit):
  ```sh
  scripts/rig-lease.sh queue list [--rig|--offline]   # what's there
  scripts/rig-lease.sh queue next --offline           # next open offline task (grab it)
  scripts/rig-lease.sh queue next --rig               # next approved rig experiment (needs lease)
  scripts/rig-lease.sh queue add <you> <slug> "<desc>" --needs offline|rig [--track T --pri P1 --dep NNN]
  scripts/rig-lease.sh queue approve 001-006 --by cj  # rig tickets only; offline needs no approval
  scripts/rig-lease.sh queue show <seq>               # full JSON
  ```
- **`.rig/`** — the lease only (ephemeral, gitignored). Not the backlog.

Each ticket has `needs: offline | rig`. **Offline tickets** (`state: open`) need
no rig and no approval — any agent grabs one and does it; that's where parallel
speed comes from, so favour them. **Rig tickets** (`state: proposed` →
`approved` → `done`) need the lease and CJ's approval, and their depth is
bounded by data-dependency (you can't spec step N+2 before step N runs), so the
rig list stays short and the deep pipeline stays here as offline analysis.

**Pre-approval semantics:** `queue approve` authorizes the *plan*. The per-image
safety gate still stands — before an agent boots a new-MMIO image, the other
agent cross-reviews the exact hashes against `~/Code/m1n1/AGENTS.md`
(§ Cross-agent review in COORDINATION.md).

## Priority & dependency order (updated 2026-07-21)

Critical path is Stage D (a usable machine). Internal NVMe is NO-GO near-term
(008: SPTM-gated, no raw-boot guarded entry), so the storage critical path is
**USB-attached root**. In rough order of leverage:

1. **USB-root pipeline** (storage, P1 — the Stage D exit). Artifacts are built
   and hash-pinned (032/050 done; gate 1 cleared). Sequence:
   **057** (approved: ADT port-map capture, read-only) → single-port host DT →
   **SMOKE rig boot** (preflight + cross-review done; re-propose with final
   hashes after 057) → **060** rootfs recipe (script now, populate only after
   smoke passes) → ROOT-mode `switch_root` rig boot → **024** interim
   untethered boot (raw enrollment). Known risk carried from the gadget era:
   post-enumeration deafness; smoke's ≥10 s liveness check is the test.
2. **PCIe → WiFi/BT** (pcie, P1). Op-115 stalls on its read side; **058** is
   the offline route-finding for the missing PHY-IP aperture precondition; only
   a new evidence-backed manifest goes live. **044** (port-0/BCM4388 manifest)
   is the pre-reviewed stage after link-up; then firmware (staged, ticket 030
   corpus).
3. **Two-way remote console** (console, P2 but high leverage for every later
   rig experiment). RX ingress is the blocker (049 done): **059** builds the
   timing-only discriminator (no new MMIO); TX-priming is the separate gated
   step 2 only if 059's run still shows zero ingress.
4. **Make the approved rig queue runnable** (smp/cpufreq/hid). 004/005/006 are
   approved with hashes TBD — **034** (SMP DT preflight), **035** (cpufreq DT
   preflight), **016** (provision tpmtfw from the paired ESP/IPSW) produce the
   pinned images so whoever holds the rig can drain them back-to-back.
5. **Upstreaming proven work** (xcut, P1): **019** SMP/cpufreq drafts, **046**
   m1n1 T6040 series, **047** DT consolidation, **048** host tools; PMGR series
   is draft-ready (CJ asks flokli re J773s policy and posts).
6. **Stage-D comforts, offline-preparable**: **061** SMC DT wiring (battery,
   power button, lid — read-only keys). **037** RTKit 26.x per-driver drafts.
7. **SPTM internal-NVMe long shot** (storage, background): 051/052/054/055 —
   static decode + the XNU-shim escalation draft for #asahi-dev. No rig time.
8. **Track-and-test** ([UPSTREAM] tickets): 022 DCP, 023 ATC PHY, 026
   installer, 039 GPU — watch, report, don't build here.

## Lanes (avoid duplicate work; not exclusive ownership)

Per COORDINATION.md roles, extended for the USB-root era:

| Lane | Primary | Current contents |
|---|---|---|
| Storage: USB-root rig pipeline + SPTM | **sol** | 057 → smoke → ROOT boot; 051/052/054/055 |
| PCIe/WiFi-BT, DockChannel console | **claude** | 058, 044; 059 |
| Rig-queue preflights, SMC/PM, upstream drafts | **claude** (first grab) | 034, 035, 016, 061; 019/046/047/048 |
| Rootfs recipe, xcut, tracking | either (queue order) | 060, 029/030, 022/023/026/039 |

The other agent still cross-reviews every live image regardless of lane, and
either agent picks up an abandoned lane rather than waiting.

`[UPSTREAM]`-tagged tickets (DCP, ATC PHY, installer, GPU) are track-and-test,
**not** build-here — this machine's unique value is Stages A–B and the DT/
enablement halves of C–E. See ROADMAP.md for the full stage map.

## Known dead-ends — do NOT propose (graves)

- Direct NVMe main/secure-BAR register writes, or the SPTM GENTER call unchanged
  (hangs; SPRR/GXF disabled on raw boot).
- SBU analog serial (confirmed dead on ACE3).
- USB gadget console (EP0 dies post-enumeration).
- Inventing ATC PHY per-bucket reg offsets.
- Any blind MMIO probing, or any SPMI/PMU/charger/NVRAM write.
- Calling IRQ 360 "dead" — the old 4096-input AIC scan used the wrong RX bit.
