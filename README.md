# qubes-ansible

Ansible automation for a [Qubes OS](https://www.qubes-os.org/) workstation.
Provisions, configures, and wires together the VM stack from a single entry point.

---

## Goal

Qubes OS is built around strong VM isolation, but managing dozens of VMs by hand
is error-prone and hard to reproduce. This project replaces manual `qvm-*` commands
and GUI clicks with idempotent Ansible playbooks that can rebuild any part of the
system from scratch, or be re-run safely against an already-running setup to push
incremental changes.

Specifically it automates:

- **Dom0** — secure-boot key management and kernel hook installation
- **LLM stack** — NVIDIA driver/CUDA installation, Ollama service, model pulling,
  GPU PCI passthrough, and TCP proxy wiring so `claude-code` can reach the model
- **OCR stack** — PDF OCR service backed by the LLM DispVM, with its own TCP proxy
- **sys-gpu** — a shared GPU DispVM template for workloads that need the card but
  not Ollama
- **Messaging** — Signal, WhatsApp (Whatsie), and Chrome in an isolated Fedora AppVM
- **Base packages** — `htop` and `tmux` on every Linux template and standalone VM

---

## Design choices

### Why a wrapper script instead of plain `ansible-playbook`

Ansible evaluates the `hosts:` field of every play *before* it loads `vars_files`.
This means any variable used in a `hosts:` pattern must be injected via `-e` (extra
vars) or be in the inventory — it cannot live in a vars file.

`ansible-playbook.sh` solves this transparently. It reads every file under
`playbooks/vars/` plus `group_vars/all.yml`, resolves simple Jinja2 references,
and passes every variable whose name starts with `host_` as an `-e` flag before
forwarding all arguments to `ansible-playbook`.

### `host_` prefix convention

Variables used directly in a `hosts:` pattern are named `host_<feature>_<descriptor>`
(e.g. `host_llm_template`, `host_ocr_dvm`). The prefix is the signal to the wrapper
that the variable must be pre-injected. All other variables are loaded normally via
`vars_files` at play execution time.

### VM provisioning pattern

Every feature with a DispVM follows the same four-phase sequence:

```
Template → DVM → DispVM → Networking
```

1. **Template** — clone a base Qubes template, temporarily enable networking,
   install packages and services inside the VM, then remove networking and shut down.
   The `base_packages` role runs here first on every template to establish a baseline.
2. **DVM** — create an AppVM with `template_for_dispvms=true`. This is the
   *persistent layer*: bind-dirs are configured here and models are pulled into
   this VM's private volume so they survive DispVM restarts.
3. **DispVM** — create the final stateless VM (`class DispVM`) with PCI passthrough,
   fixed memory, and the DVM as its template. Restarting this VM always starts
   fresh from the DVM snapshot.
4. **Networking** — add a `qubes.ConnectTCP` policy rule in Dom0 and write a
   `qvm-connect-tcp` line into the client VM's `rc.local` so the TCP tunnel is
   re-established on every boot.

### Variable scoping

Variables are split by the scope at which they are meaningful:

| Scope | Location |
|-------|----------|
| Truly global (paths, netvm, Debian version) | `playbooks/group_vars/all.yml` |
| Feature-specific (VM names, ports, memory) | `playbooks/vars/<feature>.yml` |
| Role defaults (URLs, folder paths) | `roles/<role>/defaults/main.yml` |

Each play loads only the vars files it needs. The LLM DispVM play additionally
loads `vars/sys_gpu.yml` to get the GPU PCI IDs. The OCR DVM play loads
`vars/llm.yml` to know the LLM port and DispVM name.

### Windows exclusion

Windows VMs are listed in an explicit `windows_vms` inventory group. Any play that
must skip Windows uses the `:!windows_vms` host pattern exclusion. The `base_packages`
role also guards every task with `when: ansible_os_family == 'Debian'` or
`when: ansible_os_family == 'RedHat'`, so it is harmless even if a Windows host
is accidentally targeted.

### Disabled tasks

`when: 0 > 1` marks tasks that are intentionally disabled. This keeps the YAML
structure intact (variables still need to be defined, the intent is documented)
without removing the code.

---

## File structure

```
.
├── ansible-playbook.sh          # Wrapper — always use this instead of ansible-playbook
├── ansible.cfg                  # Sets inventory = ./inventory and roles_path = ./roles
├── site.yml                     # Top-level entry point; imports all feature playbooks
│
├── inventory/
│   └── hosts.yml                # All VMs grouped by type; windows_vms group for exclusion
│
├── playbooks/
│   ├── base.yml                 # Installs base packages on all Linux templates + standalones
│   ├── dom0.yml                 # Dom0: secure boot key management
│   ├── llm.yml                  # LLM stack: template → DVM → DispVM → networking
│   ├── ocr.yml                  # OCR stack: template → DVM → DispVM → networking
│   ├── sys_gpu.yml              # sys-gpu: template → DVM → DispVM
│   ├── messenging.yml           # Messaging: template packages + AppVM autostart
│   │
│   ├── group_vars/
│   │   └── all.yml              # Global vars: paths, netvm, debian_version
│   │
│   ├── vars/
│   │   ├── llm.yml              # host_llm_template, host_llm_dvm, llm_memory, llm_tcp_port …
│   │   ├── ocr.yml              # host_ocr_template, host_ocr_dvm, ocr_tcp_port …
│   │   ├── sys_gpu.yml          # host_sys_gpu_template, gpu_pci_id_vga, gpu_pci_id_audio …
│   │   └── messenging.yml       # host_messenging_template, host_messenging_vm …
│   │
│   └── tasks/
│       └── qubes_clone_template.yml   # Reusable: clone + set netvm + set qrexec_timeout
│
└── roles/
    ├── base_packages/           # htop + tmux + ... on any Linux VM (apt or dnf via ansible_os_family)
    ├── llm_template/            # NVIDIA drivers, CUDA, Ollama service + systemd overrides
    ├── llm_dvm_1/               # Qubes bind-dirs for /usr/share/ollama (model persistence)
    ├── llm_dvm_2/               # Pull Ollama models; create custom 32k/8k context variants
    ├── ocr_template/            # Python3 + venv tooling
    ├── ocr_dvm/                 # Clone local-llm-pdf-ocr, UV venv, .env, start.sh, rc.local
    ├── sys_gpu_template/        # NVIDIA drivers + CUDA (no Ollama)
    ├── sys_gpu_dvm/             # Empty — no additional DVM config needed
    ├── secureboot/              # sbctl backup/restore scripts + kernel install hook
    ├── messenging/              # Chrome, Snap, Signal, Whatsie; autostart symlinks
    └── qubes_set_timeout/       # Reusable: set qrexec_timeout on any target VM
```

### LLM networking topology

```
claude-code (AppVM)
    │  qvm-connect-tcp 11434:@default:11434  (rc.local)
    ▼
qubes.ConnectTCP policy → llm-disp (DispVM, GPU passthrough)
                               │  Ollama :11434

ocr-disp (DispVM)
    │  qvm-connect-tcp 11434:@default:11434  (rc.local)
    ▼
qubes.ConnectTCP policy → llm-disp
```

---

## Testing before running

Ansible syntax checks validate YAML structure and module references without
connecting to any VM. Run this after every change:

```bash
# Check a single playbook
./ansible-playbook.sh playbooks/llm.yml --syntax-check
./ansible-playbook.sh playbooks/ocr.yml --syntax-check
./ansible-playbook.sh playbooks/sys_gpu.yml --syntax-check
./ansible-playbook.sh playbooks/messenging.yml --syntax-check
./ansible-playbook.sh playbooks/base.yml --syntax-check

# Or via site.yml with a tag
./ansible-playbook.sh site.yml --tags llm --syntax-check
```

**Expected false positive:** outside Dom0, every playbook that uses the `qubesos`
module reports `couldn't resolve module/action 'qubesos'`. This collection is only
installed on Dom0 and is not an error introduced by your change. All other errors
must be fixed before running.

To see which tasks would execute without making any changes:

```bash
./ansible-playbook.sh site.yml --tags llm --list-tasks
./ansible-playbook.sh site.yml --tags llm --check
```

> `--check` (dry-run) has limited usefulness here because many tasks use `command`
> and `shell` modules that always report "skipped" in check mode. Use it as a
> sanity check on variable resolution and conditionals, not as a guarantee.

---

## Running

All commands must be run from **Dom0**, at the project root.
Always use `./ansible-playbook.sh` — never `ansible-playbook` directly.

### Run a single feature end-to-end

```bash
# Provision the full LLM stack (template → DVM → DispVM → networking)
./ansible-playbook.sh site.yml --tags llm

# Provision the OCR stack
./ansible-playbook.sh site.yml --tags ocr

# Provision the GPU passthrough VM
./ansible-playbook.sh site.yml --tags sys-gpu

# Provision the messaging AppVM
./ansible-playbook.sh site.yml --tags messenging

# Apply Dom0 secure-boot configuration
./ansible-playbook.sh site.yml --tags dom0
```

### Install or update base packages on all Linux VMs

This targets every Linux template and standalone VM in the inventory. Safe to
re-run at any time against already-running systems.

```bash
./ansible-playbook.sh site.yml --tags base

# Or directly against the playbook (same effect)
./ansible-playbook.sh playbooks/base.yml
```

### Run everything

```bash
./ansible-playbook.sh site.yml
```

### Resume from a specific task

Useful when a long playbook fails partway through and you want to skip the steps
that already succeeded.

```bash
# Resume LLM provisioning from model pulling
./ansible-playbook.sh site.yml --tags llm --start-at-task "Pull Gemma 4 E4B model"

# Resume OCR provisioning from the DVM networking step
./ansible-playbook.sh site.yml --tags ocr --start-at-task "Set network policy for OCR → LLM"
```

### Override a variable at runtime

```bash
# Increase LLM DispVM memory for a session
./ansible-playbook.sh site.yml --tags llm -e "llm_memory=16000"

# Point the LLM template at a different base
./ansible-playbook.sh site.yml --tags llm -e "llm_base_template=debian-13-xfce-custom"

# Change which AppVM gets the LLM TCP tunnel
./ansible-playbook.sh site.yml --tags llm -e "host_llm_claude_code=my-other-vm"
```

### Target a specific VM directly

```bash
# Run only the base_packages role on a single template that is already running
ansible -i inventory/hosts.yml llm-template-debian-13-xfce \
  -m include_role -a name=base_packages --become
```

### Limit execution to a subset of hosts

```bash
# Re-run the LLM playbook but only the plays that target Dom0 (local)
./ansible-playbook.sh playbooks/llm.yml --limit localhost

# Re-run base on Debian templates only
./ansible-playbook.sh playbooks/base.yml --limit 'debian*'
```
