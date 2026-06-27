# 0001 — Self-sustaining symmetric per-node orchestrators

## Status

Accepted — 2026-06-27.

## Context

The fleet should be **self-sustaining**: after initial bootstrap, the management host
(WSL) is used only for development (writing code, the very first build, pushing to git).
Nothing in the steady-state runtime path should depend on the laptop — including
**Windows template regeneration** (the eval clock expires ~every 180 days; we rebuild at
~100 to stay ahead, which also picks up updates).

Storage is shared Ceph, so a template is cluster-wide (build once, clone anywhere). The
prior design specified one tiny bash-only orchestrator LXC per node for runner lifecycle
only, with image builds done from WSL.

## Decision

Each Proxmox node runs **one orchestrator LXC that is a full "node agent"** — symmetric,
autonomous, owning everything for its node:

1. **Runner lifecycle** (frequent, systemd timer ~1-5 min): detect used/stopped ephemeral
   runner → reset (snapshot rollback or re-clone from the node's template) → request a
   fresh org registration token → inject → start a clean runner for one job.
2. **Image regeneration** (rare, fixed staggered schedule ~60-90 days): `git pull` the
   repo and run `packer build` to regenerate **its node's** Windows (and Linux) template.

Consequences of "each node builds its own template":

- Each orchestrator carries Packer + a checkout of this repo + build tokens (Proxmox with
  build privileges, WinRM/build password) + CephFS ISO access. The LXC stays modest
  (~1-2 GB): Packer only drives the Proxmox API; the heavy VM build runs on the node.
- **Per-node template identity** (distinct `vm_name`/template VMID per node) so the three
  orchestrators do not collide on the shared Ceph storage.
- Builds are staggered (different schedule offsets per node) to avoid simultaneous load.

WSL's only roles: write code, the first bootstrap build/clone, and `git push`.

## Consequences

- **Pro:** no single "builder" SPOF; every node identical and self-contained; the model is
  conceptually simple ("each orch does everything for its node"); regeneration never
  touches WSL.
- **Con (accepted):** on Ceph the per-node templates are redundant (one cluster-wide
  template would suffice) — 3× build runs and 3× template copies. Builds are rare,
  staggered, and cheap on thin Ceph, so the symmetry/autonomy is worth it.
- The Windows eval-age checker (`orchestrator/check-windows-template-age.sh`) changes from
  alert-only toward a fixed-schedule rebuild trigger (a cron/timer running the build), per
  this ADR's fixed-schedule choice.

## Open work (see roadmap)

- Finish `reset_runner_slot` in `gha-local-orchestrator.sh` (clone/rollback + token
  inject + start) — needed regardless.
- Orchestrator provisioning: install Packer + repo + tokens + units on each LXC.
- Per-node template naming in the Packer builds.
- Scheduled `git pull` + `packer build` units (staggered).
