#!/bin/sh
# Socket-activated: a runner VM pokes the LAN trigger socket right after its job finishes
# (just before it shuts down). Reconcile immediately instead of waiting for the poll timer.
#
# The VM is still shutting down when the poke arrives, so loop briefly to catch it the
# moment it's 'stopped'. `systemctl start` on the oneshot orchestrator serializes runs
# (blocks while a reset is in flight), so resets never overlap. The 15s timer is the
# fallback if the poke is missed.
i=0
while [ "$i" -lt 8 ]; do
  systemctl start gha-local-orchestrator.service
  sleep 2
  i=$((i + 1))
done
