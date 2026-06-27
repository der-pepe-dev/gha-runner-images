# Required tools

Tools a management host needs to build/validate these images. This list is durable
and committed. For what a *specific* machine currently has, see [[environment]]
(per-machine snapshot, gitignored — regenerate with `scripts/snapshot-environment.sh`).

> CI note: there are no GitHub Actions workflows in this repo, so no linter is
> enforced on push. The validation tools below are project convention, run locally.

## Required — image build / provisioning

| Tool | Purpose | Install (Ubuntu/WSL2) |
|------|---------|------------------------|
| `packer` | Build/validate VM image templates | HashiCorp apt repo → `apt install packer` |
| Proxmox Packer plugin | `github.com/hashicorp/proxmox` >= 1.2.3 | `packer init packer/linux/ubuntu-gha-core.pkr.hcl` |
| `ansible` | Provision cloned VMs | `pipx install --include-deps ansible` |
| `ansible-playbook` | Run/syntax-check playbooks | bundled with `ansible` |
| `ansible-vault` | Encrypt/decrypt real secrets | bundled with `ansible` |
| `pwsh` | PowerShell 7 helper/clone scripts | PowerShell 7 |
| `git`, `gh` | VCS + GitHub API | `apt install git`, GitHub CLI |

## Required — validation / lint (project convention)

| Tool | Purpose | Install |
|------|---------|---------|
| `ansible-lint` | Lint Ansible roles/playbooks | `pipx inject ansible ansible-lint` |
| `shellcheck` | Lint bash scripts (`scripts/*.sh`) | `apt install shellcheck` |
| `yamllint` | Lint YAML | `pipx install yamllint` |

`packer fmt -check` and `packer validate` ship with `packer`.

## On the Proxmox host only

| Tool | Purpose |
|------|---------|
| `qm` | Proxmox VE VM CLI (clone/manage templates) |
| `pvesh` | Proxmox API shell |
| `virt-customize` | Optional image customization (libguestfs) |

## Optional — faster CLI (see [[instructions/cli-tooling]])

`rg`, `fd`, `jq`, `yq`, `delta`, `hyperfine`. Preferred in shell pipelines; not
required to build.

## Validation shortcuts

```bash
packer fmt -check packer/                          # formatting
packer validate packer/linux/ubuntu-gha-core.pkr.hcl
ansible-lint
ansible-playbook --syntax-check <playbook>.yml
shellcheck scripts/*.sh
```

Never run register-runner playbooks against the golden template — clones only.
