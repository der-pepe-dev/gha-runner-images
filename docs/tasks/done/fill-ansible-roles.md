# Task: fill github_runner and dotnet_sdk roles

Move the repeated .NET-SDK and runner-registration logic out of the playbooks into
real roles, supporting both Linux (ssh) and Windows (winrm) hosts.

## Design

- Platform dispatch without gather_facts (Windows register playbooks use
  `gather_facts: false`): branch on `ansible_connection` —
  `winrm` → Windows.yml, else Linux.yml. ansible_connection is always set from
  inventory for both groups.
- **dotnet_sdk**: install .NET SDK via the official `dotnet-install` script.
  Linux → /opt/dotnet + /usr/local/bin symlink; Windows → C:\Program Files\dotnet +
  machine PATH. Channel from `dotnet_channel`.
- **github_runner**: create runner user + dirs, request a short-lived registration
  token (no_log), download/extract the pinned runner package, configure as a service.
  Linux → svc.sh; Windows → config.cmd --runasservice with the gha-runner account.
  Keeps the existing persistent-service behavior; `runner_ephemeral` flag optional.
- Rewire: linux-base/windows-base use `dotnet_sdk`; register playbooks use
  `github_runner`. Roles become the single source; playbooks stay thin.

## Checklist

- [ ] dotnet_sdk: defaults, tasks/main(dispatch), Linux.yml, Windows.yml, meta, README
- [ ] github_runner: defaults, tasks/main(dispatch), Linux.yml, Windows.yml, meta, README
- [ ] Rewire linux-base.yml + windows-base.yml -> dotnet_sdk role
- [ ] Rewire linux/windows-register-runner.yml -> github_runner role
- [ ] Verify: yamllint + python yaml parse each file (ansible not installed here)
- [ ] current-status note

## Verify

- `yamllint` the role/playbook YAML.
- `python3 -c "import yaml; yaml.safe_load(open(f))"` each new file.
- `ansible-lint` / `ansible-playbook --syntax-check` — NOT runnable (ansible not
  installed on this host); note as unverified.
