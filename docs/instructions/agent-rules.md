# Agent rules

Rules that apply to all agents (Claude Code, Codex, Copilot) working in this repo.

## Inspect before editing

- Read relevant project memory and source before proposing changes.
- Prefer the narrowest change that solves the problem.

## Verification is mandatory

- Never mark work complete without evidence (build/test/log/before-after).
- If verification cannot be run, state why and what remains unverified.

## Memory discipline

- Keep durable knowledge in `docs/`, not in local user-home memory.
- One file per active task under `tasks/<task-name>.md`.
- Update `current-status.md` and `index.md` only on durable changes.
- After a user correction, append a lesson to `tasks/lessons.md`.

## Source hygiene

- Work only in live source.
- Treat `bin/`, `obj/`, `artifacts/`, `.vs/`, build output, and nested
  extracts/snapshots as generated noise unless explicitly documented otherwise.

## Shell commands

- Check `docs/environment.md` for installed tools before assuming availability.
- Prefer the fast CLI tools listed in `instructions/cli-tooling.md` in pipelines.

## Infrastructure / secrets safety (critical for this repo)

- NEVER commit or print secrets: GitHub PATs, runner registration tokens, Proxmox API
  tokens, Windows admin passwords, ansible-vault passwords, or real inventory
  (hostnames/IPs). Committed config files are `.example.*` only.
- When editing playbooks, keep `no_log: true` on any task that handles a token, password,
  or vault value. Do not remove it.
- Real values live in gitignored files (`hosts.ini`, `fleet.ini`, `all.yml`, group_vars
  without `.example`, `*.local.yml`, `*.auto.pkrvars.hcl`) and/or ansible-vault. Never
  un-gitignore them.
- Orchestrator and helper scripts read secrets from environment variables
  (`PROXMOX_TOKEN`, `GITHUB_TOKEN`, etc.) — keep it that way; never hardcode them.
- The orchestrator LXC holds Proxmox + GitHub tokens — run it **unprivileged**, with
  only outbound network to the Proxmox API and GitHub. No privileged mounts or device
  passthrough.
- Never register a GitHub runner against the golden template — registration runs on
  CLONED VMs only (the `*-register-runner.yml` playbooks and ephemeral bootstrap).
- Runner registration tokens are short-lived; request them at registration/boot time,
  never bake them into images or store them long-lived in the orchestrator.

## Validating changes (no app build here)

- Packer: `packer validate <file>.pkr.hcl` and `packer fmt -check`.
- Ansible: `ansible-lint` and `ansible-playbook --syntax-check <playbook>.yml`.
- PowerShell orchestrator/scripts: `pwsh -NoProfile -Command "..."` syntax check where
  practical. These are the "did it build/test" equivalents — use them as verification.

## Branch / PR workflow

- For every change, create a branch — `feat/<short-name>`, or `fix/<...>` /
  `chore/<...>` when more fitting. Never commit directly to `main`.
- Push the branch and open a PR against `main`.
- Wait for CI to pass, then merge the PR into `main`. If CI fails, fix on the same
  branch and push again — do not merge red.
- When addressing a PR review comment, after pushing the fix: reply to that review
  thread noting what changed (and the commit), then mark the thread resolved. Do not
  leave addressed comments unanswered or unresolved.
