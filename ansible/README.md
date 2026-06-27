# Ansible

Ansible playbooks for configuring GitHub Actions runner VMs after the OS template is built.

## Collections

Install required collections:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Inventory

Copy the example inventory and group vars:

```bash
cp inventory/hosts.example.ini inventory/hosts.ini
cp group_vars/windows.example.yml group_vars/windows.yml
cp group_vars/linux.example.yml group_vars/linux.yml
cp group_vars/vault.example.yml group_vars/vault.yml
```

Encrypt real secrets:

```bash
ansible-vault encrypt group_vars/vault.yml
```

## Usage

Configure a Windows base VM:

```bash
ansible-playbook playbooks/windows-base.yml
```

Register a cloned Windows VM as a runner:

```bash
ansible-playbook playbooks/windows-register-runner.yml --ask-vault-pass
```
