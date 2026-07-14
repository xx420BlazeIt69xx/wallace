#!/usr/bin/env bash
# rig-guard.sh — sourced by every rig-touching script so the lease is binding,
# not honor-system: two agents can never drive the one physical cable at once.
#
# SAFETY MODEL — block real collisions, never block an idle rig.
#   * If a LIVE lease is held by someone OTHER than you (or you're anonymous),
#     REFUSE (exit 5) — always, even in soft mode. This is the only situation
#     that actually corrupts the KIS link, so it is unconditionally fatal. The
#     RIG_BYPASS escape hatch still overrides it for genuine manual recovery.
#   * If the rig is FREE (no lease, or the holder's lease has expired = the
#     holder is gone), PROCEED. An idle rig is safe to drive, so a solo run by
#     an agent that hasn't adopted the lease is never broken by this guard.
#   * The softer nudges ("you didn't acquire", "your lease expired",
#     "needs recovery") only WARN — unless you opt into strict mode with
#     RIG_ENFORCE=1, which makes them fatal too.
#
# This is what makes it safe to wire into the live scripts before both agents
# have fully adopted the lease: it protects a holder from the other agent, but
# it cannot false-positive an idle-rig run into a broken experiment.
#
# Contract (set BEFORE `source`-ing this):
#   RIG_AGENT              who you are ("claude", "sol", "maintainer").
#   RIG_ENFORCE=1          strict: the soft nudges exit 5 instead of warning.
#   RIG_ALLOW_RECOVERY=1   set by the recovery-boot script; lets it run while
#                          NEEDS_RECOVERY is set (fixing the link is its job).
#   RIG_BYPASS=1           escape hatch; skips the check entirely (loud).
_rig_guard() {
  local root="${RIG_ROOT:-$HOME/Code/wallace/.rig}"
  local lease="$root/lease.env" flag="$root/NEEDS_RECOVERY" self="${RIG_AGENT:-}"
  local strict="${RIG_ENFORCE:-0}"
  if [ "${RIG_BYPASS:-0}" = 1 ]; then
    echo "rig-guard: BYPASS set — skipping lease check." >&2; return 0
  fi

  # Effective current holder: empty if no lease or the lease has expired.
  local holder="" e=""
  if [ -f "$lease" ]; then
    holder="$(sed -n 's/^HOLDER=//p' "$lease" | head -1)"
    e="$(sed -n 's/^EXPIRY=//p' "$lease" | head -1)"
    if [ -z "$e" ] || [ "$(date +%s)" -ge "$e" ]; then holder=""; fi   # expired → gone
  fi

  # THE TEETH: a live lease held by someone else is a collision. Always fatal.
  if [ -n "$holder" ] && [ "$holder" != "$self" ]; then
    echo "rig-guard: REFUSE — rig is HELD by '$holder', you are '${self:-anonymous}'. Driving now would corrupt the KIS link. Wait for release, or 'scripts/rig-lease.sh status'. (RIG_BYPASS=1 overrides, for manual recovery only.)" >&2
    exit 5
  fi

  # deny(reason): fatal only in strict mode; otherwise warn and proceed.
  _deny() {
    if [ "$strict" = 1 ]; then echo "rig-guard: REFUSE — $1" >&2; exit 5
    else echo "rig-guard: WARN — $1 (proceeding; RIG_ENFORCE=1 makes this fatal)" >&2; fi
  }

  if [ -z "$self" ]; then
    _deny "RIG_AGENT unset; acquire first: scripts/rig-lease.sh acquire <agent> \"<task>\" [sha]"; return 0
  fi
  if [ "$holder" != "$self" ]; then
    # rig is free but you didn't acquire (or your own lease expired)
    _deny "rig is free but you don't hold a live lease; acquire it first: scripts/rig-lease.sh acquire $self \"<task>\" [sha]"; return 0
  fi
  if [ -f "$flag" ] && [ "${RIG_ALLOW_RECOVERY:-0}" != 1 ]; then
    _deny "NEEDS_RECOVERY set (link untrusted); run a recovery boot first, then: scripts/rig-lease.sh recovered $self"; return 0
  fi
  echo "rig-guard: ok — '$self' holds the rig ($(( e - $(date +%s) ))s left)." >&2
}
_rig_guard
