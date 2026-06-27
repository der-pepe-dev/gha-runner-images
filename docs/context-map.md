# gha-runner-images context map

Use this file to decide which memory files to read for a task. Do not read every
file by default.

## Always read at session start

- [[index]]
- [[current-status]]
- [[environment]]
- [[instructions/agent-rules]] — includes the critical secrets-safety rules
- [[tasks/lessons]]

## Runner architecture / image model

Read when touching the Packer→Ansible flow, image definitions, or runner registration.

- [[runner-architecture]]
- [[consumers]] — which projects depend on which runners/tools
- [[proxmox]]

## Consumer tool requests

Read when a consuming project needs a tool installed on a runner.

- [[consumers]] — the hub list; update the project's row when adding a tool to a role

## Fleet / orchestrator / ephemeral runners

Read when touching the local orchestrator, fleet layout, ephemeral bootstrap, or
per-node runner placement.

- [[runner-fleet]]
- [[nas-runner-group]]
- `orchestrator/` (orchestrator script, systemd unit/timer, bootstrap scripts)

## Packer (golden templates)

Read when editing image builds (`packer/linux/`, `packer/windows/`).

- [[runner-architecture]]
- [[linux-runner]]
- [[windows-runner]]

## Ansible (provisioning + registration)

Read when editing playbooks/roles under `ansible/`.

- [[runner-architecture]]
- [[instructions/agent-rules]] — secrets/no_log/clone-only registration rules

## Proxmox / host

Read when touching Proxmox templating, cloning, or host config.

- [[proxmox]]
- [[deploy]] — building/deploying templates onto the cluster (Ceph, ISO upload, API reachability)

## Tooling / validation

- [[instructions/cli-tooling]]
