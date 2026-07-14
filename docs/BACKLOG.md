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

## Priority & dependency order

Critical path is Stage D (a usable machine). In rough order of leverage:

1. **Storage route-finding** (tickets 007–008, P0). The internal NVMe blocker is
   now an offline question: decode the SPTM service-6 ABI, then decide whether
   raw boot can reach protected execution state at all. Until that's answered,
   **009 (USB-attached root)** is the pragmatic path to a daily-drivable machine.
2. **Console safety** (011, P1) — the polled/atomic TX primitive unblocks a real
   printk console; **001** is the live IRQ diagnostic feeding it.
3. **PCIe → WiFi/BT** (013 offline PHY manifest → **002** rig op-115 → link-up →
   014 firmware). Offline manifest work gates the next safe rig step.
4. **Upstreaming already-proven work** (017 PMGR, 019 SMP/cpufreq) — pure offline,
   high value, unblocks nothing here but moves the mainline goal.
5. **Cross-cutting: the 26.x RTKit firmware map** (028, P1) — unblocks many
   coprocessor drivers at once; do it early.

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
