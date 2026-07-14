# Onboarding: sharing the rig with `claude`

You (`sol`) and `claude` both work this repo toward mainline Linux on the M4 Pro.
Almost everything parallelizes fine — the one thing that does **not** is the
physical rig. This note is how to take turns on it. Full protocol:
[COORDINATION.md](COORDINATION.md).

## The one rule

There is exactly one rig: the M4, one DebugUSB cable, one m1n1 proxy, one
`/tmp/m1n1` pty. **Two agents touching it at once corrupts the KIS link**
(unattended pty buffers wedge it into an apparent one-way stream; recovery costs
a reboot). So before you run *any* rig-touching script — `t6040-boot-dcuart.sh`,
`t6040-debugusb-console.sh`, `t6040-bootcap-fb.sh` — you take a **lease**, and
you release it when done.

The lease tool is `scripts/rig-lease.sh`. State lives in `.rig/` (gitignored,
shared between us on this host's filesystem).

## Wrap every rig session in a lease

```sh
cd ~/Code/wallace

# 1. Is it free? (see caveat below)
scripts/rig-lease.sh status

# 2. Take it — name yourself "sol", give the task + the m1n1 SHA you're testing.
scripts/rig-lease.sh acquire sol "nvme ans-read isolation" 88ce1ee3

# 3. Drive the rig as usual (recovery boot, chainload, run the experiment)…
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-dcuart.sh
#    …for a long step, extend your lease so it can't be reclaimed under you:
scripts/rig-lease.sh renew sol

# 4. Record the result the usual way (commit + a done/ write-up).

# 5. Hand the rig back. Say whether the link is healthy or wedged:
scripts/rig-lease.sh release sol --state healthy
#    If the link is wedged or you're unsure:
scripts/rig-lease.sh release sol --state wedged
```

`acquire` succeeds if the rig is free (or already yours). If `claude` holds it,
`acquire` prints who/what and exits **3 (BUSY)** — don't touch the rig; do
offline work and try later.

## Two hard invariants

1. **Never drive unless you hold the lease.** If `status` shows it HELD by
   `claude`, stay off the cable.
2. **Leave it as you'd want to find it.** Release `--state healthy` only after
   the proxy is back to a quiescent `Running proxy`. Otherwise release `--state
   wedged` — that sets a `NEEDS_RECOVERY` flag, and the next acquirer (maybe you)
   must run a recovery boot before trusting the link, then clear it:
   `scripts/rig-lease.sh recovered sol`. Silently handing off a wedged cable is
   the one unforgivable move.

## The schedule = the approved queue

We only ever put the rig to *approved, hashed* experiments. Propose yours,
CJ (the maintainer) approves, then whoever's free runs the next approved one:

```sh
scripts/rig-lease.sh queue add sol nvme-ans-read "single readl of ANS CPU_CONTROL 0x209600044" 88ce1ee3
scripts/rig-lease.sh queue next     # lowest approved entry — that's the turn order
scripts/rig-lease.sh queue done 003 # after you've run + recorded it
```

Do **not** hold the lease while waiting for CJ to approve the next step — that
starves `claude` for as long as CJ is away. Approval happens offline, ahead of
rig time; you acquire only when there's already-approved work to run.

Auto-acquire is on and either of us may drive: when the lease is free and
`queue next` returns approved work, take it. When idle, don't spin — do your
offline track and re-check `status` on a boot-cycle cadence (minutes).

## How the guard treats you (it's wired into the live scripts now)

`scripts/rig-guard.sh` is sourced by the three rig scripts. What it does to you:

- If **`claude` holds a live lease**, the rig scripts **refuse to run** (exit 5)
  — this stops you from corrupting the link. Wait, or check
  `scripts/rig-lease.sh status`. (`RIG_BYPASS=1` overrides, for manual recovery
  only.)
- If the **rig is idle**, the scripts run even if you forgot to acquire — you'll
  just get a WARN. So the guard won't break a solo run; it only blocks a real
  collision.
- Please still `acquire` before driving: it's what makes `status` correct for
  `claude` and protects *your* run from being interrupted. Once we're both
  reliably acquiring, CJ may set `RIG_ENFORCE=1` to make "you forgot to acquire"
  fatal too.

One transition caveat: **`status` only reflects an agent that actually took a
lease.** If one of us drives without acquiring, `status` still says FREE — so
until we're both acquiring every time, keep coordinating out-of-band too.

## Before a live image goes to CJ for approval

A wrong MMIO offset raises an async SError that kills m1n1. So before proposing
a live image, `claude` reviews it against the non-negotiables in
`~/Code/m1n1/AGENTS.md` (no SPMI/PMU/NVRAM writes, no blind MMIO, ADT-derived
addresses only, hashes pinned, intentional stop before the first dangerous
write) — and you do the same for `claude`'s. Note the reviewer in the queue
entry. CJ approves last.
