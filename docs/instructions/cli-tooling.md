# CLI tooling

Fast CLI tools preferred over slower POSIX equivalents in shell pipelines. Check
`environment.md` for which are actually installed on the current host.

- `rg` (ripgrep) — code/text search, instead of `grep -r`.
- `fd` — file finding, instead of `find`.
- `jq` — JSON querying (CLI output, config, lockfiles).
- `yq` — YAML query/validate (e.g. CI workflow files).
- `delta` — readable git diffs (`git -c core.pager=delta diff`).
- `hyperfine` — command benchmarking (before/after timing).

Use dedicated editor/search tools when available; reach for these in shell pipelines.

- `packer` — build/validate VM image templates (`packer validate`, `packer fmt`).
- `ansible` / `ansible-lint` / `ansible-playbook` — provisioning + linting + syntax-check.
- `ansible-vault` — encrypt/decrypt real secret values (never commit decrypted).
- `pwsh` — PowerShell 7 for the helper scripts (`get-runner-token.ps1`, clone script).
- `qm` / `pvesh` — Proxmox VE CLI/API (when on the PVE host).
