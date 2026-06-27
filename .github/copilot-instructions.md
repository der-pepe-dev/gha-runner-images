# GitHub Copilot instructions for gha-runner-images

These instructions apply when assisting with gha-runner-images.

Copilot does not follow file references, so the essentials are inlined here. The
fuller knowledge base lives in `docs/` (read by Claude Code and Codex).

## Project

- gha-runner-images: Packer + Ansible automation for building Proxmox-hosted GitHub Actions self-hosted runner images
- Stack: Infrastructure-as-Code (Packer, Ansible, PowerShell) targeting Proxmox VE
- Environment: WSL2 management host

## Repository layout

- `packer/linux/`, `packer/windows/` — Packer HCL image definitions + provisioning scripts.
- `ansible/playbooks/` — base config + runner registration playbooks.
- `ansible/roles/` — reusable roles (currently placeholder stubs).
- `ansible/group_vars/`, `ansible/inventory/` — config; committed copies are `.example.*` only.
- `scripts/` — PowerShell helpers (Proxmox clone, runner-token request).
- `secrets/` — gitignored except README; never commit real secrets here.

## Engineering principles

- Keep code practical, simple, explicit, and debuggable.
- Concrete code over speculative framework work.
- Minimal-impact edits: touch only what is necessary.
- Root-cause fixes over temporary hacks.

## Coding conventions

- This is IaC (Packer + Ansible + PowerShell), not an application — no app build.
- Keep `no_log: true` on any Ansible task handling tokens/passwords/vault values.
- Idempotency: use `creates:` guards and `--replace` on runner config.
- Register runners on CLONED VMs only, never the golden template.
- Use explicit runner labels, not `ubuntu-latest`/`windows-latest`.
- Committed config is `.example.*`; real values are gitignored / ansible-vault encrypted.

## Do not

- Do not introduce broad speculative abstractions.
- Do not edit generated folders (`bin/`, `obj/`, build output).

- Do not commit secrets, tokens, passwords, or real inventory (hostnames/IPs).
- Do not remove `no_log: true` from secret-handling tasks.
- Do not bake runner registration tokens into images.
- Do not register runners against the golden template.
