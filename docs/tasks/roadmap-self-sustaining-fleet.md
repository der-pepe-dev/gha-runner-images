# Roadmap: self-sustaining symmetric orchestrators

Target architecture: see [[decisions/0001-self-sustaining-symmetric-orchestrators]].
Goal: after bootstrap, WSL is dev-only; each node's orchestrator owns its runners AND
its template regeneration.

## Phase 0 — Foundations (DONE)

- [x] Windows golden template builds (virtio, updates, host CPU) — reproducible
- [x] Linux golden template builds (autoinstall) — reproducible
- [x] Registration logic (github_runner role) works, org-scope supported
- [x] discover-proxmox.sh fills pkrvars + fleet.local.yml

## Phase 1 — Prove one runner (validates reused registration logic)

- [ ] Clone one VM from a template, Ansible-register it (org-level), confirm it appears
      in der-pepe-dev runners and runs a job. This is the same registration the
      orchestrator will call — proving it de-risks the orchestrator.

## Phase 2 — Finish the runner-lifecycle loop (orchestrator job #1)

- [ ] Implement `reset_runner_slot` in `orchestrator/gha-local-orchestrator.sh`:
      pick reset strategy (snapshot-rollback vs destroy+reclone), inject fresh org
      registration token + runner name/labels/ephemeral via cloud-init/guest-agent,
      start the VM.
- [ ] Confirm the per-node reconcile timer brings a used ephemeral runner back to clean.

## Phase 3 — Orchestrator as node agent (provisioning)

- [ ] Orchestrator provisioning playbook/script: install Packer + git checkout of this
      repo + build tokens (Proxmox build-priv token, build password) + CephFS ISO access
      on each orchestrator LXC. Size LXC ~1-2 GB (Packer only drives the API).
- [ ] Decide token storage/rotation on the LXC (EnvironmentFile, least privilege).

## Phase 4 — Self-regenerating images (orchestrator job #2)

- [ ] Per-node template identity in the Packer builds (vm_name/template VMID per node)
      so the 3 orchestrators don't collide on shared Ceph.
- [ ] systemd timer per orchestrator: `git pull` + `packer build` on a fixed,
      staggered schedule (~60-90 days). Re-point the eval-age checker as a safety net.
- [ ] Runner-reset clones from the node's own template VMID.

## Phase 5 — Confirm self-sustaining

- [ ] Run the fleet for a full regen cycle with WSL powered off; verify runners keep
      cycling and templates regenerate with no laptop involvement.

## Notes

- Phase 1 + Phase 2 are the critical path to "ephemeral runners actually work". Phase 3-4
  remove WSL from regeneration. Do them in order.
- The orchestrator README still describes the older tiny-bash-only model; update it to the
  ADR's node-agent model when Phase 3 lands.
