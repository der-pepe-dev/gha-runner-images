# Task: Windows template eval-age check

Track win-gha-core template activation (eval clock) and alert when it nears the
Windows Server evaluation limit, so it gets regenerated before expiry.

## Decisions

- Alert only (no auto-rebuild). Human runs packer when warned.
- Runs on the orchestrator (per-node, systemd timer — daily).
- No state file. Derive activation from Proxmox: template VM `meta:` `ctime`
  (creation epoch ≈ OS install ≈ eval start).
- Threshold default 100 days (Server 2022 eval = 180d; 80d buffer). Rearm noted
  in docs as an alternative to full rebuild.

## Checklist

- [x] Inspect orchestrator + windows packer build
- [ ] `orchestrator/check-windows-template-age.sh` — query ctime, warn at threshold
- [ ] `orchestrator/gha-template-age-check.service` + `.timer` (daily)
- [ ] Add `WIN_TEMPLATE_EVAL_MAX_DAYS` to example env files
- [ ] Doc: orchestrator/README.md + windows-runner.md (incl. rearm note)
- [ ] shellcheck the new script
- [ ] current-status dated note

## Verify

- `bash -n` + `shellcheck` the script.
- Dry logic check of ctime parse with a sample `meta:` string.
