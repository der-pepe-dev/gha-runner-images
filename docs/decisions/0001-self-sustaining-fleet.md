# 0001 — Self-sustaining fleet: tiny orchestrators + one HA builder

## Status

Accepted — 2026-06-27. (Supersedes an earlier same-day draft that proposed symmetric
per-node builders; never implemented.)

## Context

The fleet should be **self-sustaining**: after bootstrap, the management host (WSL) is
used only for development (writing code, the first build, `git push`). Nothing in the
steady-state runtime path — including **Windows template regeneration** (eval clock
expires ~180 days; rebuild at ~100 to stay ahead and pick up updates) — should depend on
the laptop.

Storage is shared Ceph, so a template is cluster-wide: build once, clone/seed anywhere.

## Decision

Two component types:

- **3 tiny per-node orchestrators** — small bash + curl + jq LXC (~512 MB-1 GB), one per
  node. Each owns **only its node's runner lifecycle**: snapshot-rollback the node's
  runner slot VMs, inject a fresh org registration token, register `--ephemeral`, run one
  job, rollback. **Non-HA and node-pinned** — if a node is down, its runners are down, by
  design.
- **1 dedicated builder LXC** — owns **all image regeneration**. On a fixed schedule it
  `git pull`s this repo and runs `packer build` to regenerate the **single cluster-wide
  golden template per OS** (Ceph makes it visible to all nodes). The builder is
  **Proxmox HA-enabled**: it is stateless (repo from git, secrets from an EnvironmentFile,
  templates land on Ceph), so on a node failure HA relocates it to a surviving node. Its
  rootfs lives on Ceph and the 3-node cluster has quorum, so HA is viable.

One golden template per OS, built once by the builder; orchestrators create each runner
slot once (single clone from the template) and thereafter snapshot-rollback it.

## Reset strategy: snapshot-rollback of actual VMs (not per-job cloning)

Clean-per-job ephemeral needs fast derivation (seconds) — a full Packer build (~30-40
min) cannot run per job. So the golden image is only the **periodic seed**, not a per-job
dependency. In steady state the orchestrator operates on **actual per-slot VMs**:

- Create each runner slot **once** as a real VM (single clone from the golden image), then
  take a **clean snapshot** (OS + tooling + runner binaries, *unregistered*).
- **Per job:** rollback to the clean snapshot → inject a fresh org registration token →
  register `--ephemeral` → run one job → rollback. No per-job clone, no template touch.
- **Refresh (~60-90 days):** the builder rebuilds the golden image (Packer) → orchestrators
  re-seed / re-snapshot the slot VMs to pick up updates and reset the Windows eval clock.

This is the `snapshot-rollback` MODE already present in the orchestrator config;
`destroy-reclone` remains a slower alternative.

## Template handover (old -> new)

Regenerating the template must not break running runners or point orchestrators at a
half-built image. Key enabler: **slots are full clones** (`full_clone: true`), so a runner
slot VM is independent of the template once created — the template is only consulted at
re-seed. Handover is a rolling, pointer-based swap:

1. **Build new, don't clobber.** The builder builds the new template to a **new (versioned)
   VMID**, leaving the old one intact. A successful Packer build is the validation gate
   (it booted and WinRM/SSH-connected), so a broken build never becomes "current".
2. **Atomic pointer flip.** A small `current-template` marker (a value on CephFS, or a
   Proxmox tag such as `gha-current`) names the live template VMID. The builder flips it
   only after a successful build; orchestrators read it to know what to seed from.
3. **Rolling drain re-seed.** Each orchestrator re-seeds a slot only when it is **idle**
   (between jobs): drain → destroy old slot VM → full-clone from the new template → clean
   snapshot → resume the rollback cycle. One slot at a time; in-flight jobs finish on the
   old VM; no global downtime.
4. **Retain N-1, then delete.** Keep the previous template as a rollback target (flip the
   marker back if the new one misbehaves) until all slots have re-seeded and nothing
   references it, then delete it.

## Consequences

- **Pro:** single cluster-wide template (no redundant 3× builds or storage, matches Ceph);
  builder HA removes the single-builder SPOF; orchestrators stay tiny and simple; runners
  stay trivially pinned/non-HA; regeneration never touches WSL.
- **Con:** the builder is a distinct component to provision (Packer + repo + build tokens)
  and to place in an HA group. Only one, and stateless, so this is contained.
- WSL's only roles: write code, first bootstrap build/clone, `git push`.

## Open work (see roadmap)

- Finish `reset_runner_slot` in `gha-local-orchestrator.sh` (snapshot-rollback + token
  inject + register).
- Provision the builder LXC (Packer + repo + tokens + scheduled build unit) and put it in
  an HA group.
- Provision the 3 tiny orchestrators (config + units).
