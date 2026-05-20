# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This Ansible project manages a Qubes OS system — provisioning, configuring, and wiring together its VMs.

## Running Playbooks

All playbooks must be run from Dom0 using the wrapper script at the project root:

```bash
./ansible-playbook.sh site.yml --tags base
./ansible-playbook.sh site.yml --tags dom0
./ansible-playbook.sh site.yml --tags llm
./ansible-playbook.sh site.yml --tags ocr
./ansible-playbook.sh site.yml --tags sys-gpu
./ansible-playbook.sh site.yml --tags messenging
```

**Always use `ansible-playbook.sh` instead of `ansible-playbook` directly.** The wrapper auto-injects all `host_*` variables as `-e` flags so they are available when Ansible evaluates `hosts:` patterns (which happens before `vars_files` are loaded).

`ansible.cfg` sets `inventory = ./inventory`, so no `-i` flag is needed.

To resume from a specific task:
```bash
./ansible-playbook.sh site.yml --tags llm --start-at-task "Pull Gemma 4 E4B model"
```

To override a variable at runtime:
```bash
./ansible-playbook.sh site.yml --tags llm -e "llm_memory=16000"
```

## Architecture

### Inventory Groups

- `local` — Dom0 itself (`ansible_connection=local`)
- `appvms` — Running AppVMs/DVMs (`ansible_connection=qubes`)
- `templatevms` — Template VMs (`ansible_connection=qubes`)
- `standalonevms` — Standalone VMs (`ansible_connection=qubes`)

### Variable Layout

Variables are split by scope:

| Location | Contains |
|----------|----------|
| `playbooks/group_vars/all/main.yml` | Truly global non-secret vars: VM user paths, `netvm_default`, `debian_version`, bind-dir paths, `rc_local`, networking policy path |
| `playbooks/group_vars/all/secrets.yml` | Ansible-vault-encrypted secrets: `admin_user` and any future secrets; auto-loaded for every play |
| `playbooks/vars/base.yml` | `vm_resource_config` list — per-VM overrides for `maxmem`, `memory`, and `vcpus` |
| `playbooks/vars/llm.yml` | LLM template/DVM/DispVM names, memory, TCP port, claude-code VM name |
| `playbooks/vars/ocr.yml` | OCR template/DVM/DispVM names, TCP port, data VM name |
| `playbooks/vars/sys_gpu.yml` | GPU template/DVM/DispVM names, memory limits, PCI IDs for GPU passthrough |
| `playbooks/vars/messenging.yml` | Messaging template and AppVM names, netvm |
| `roles/*/defaults/main.yml` | Role-specific defaults (`nvidia_cuda_url` in `llm_template` and `sys_gpu_template`; `sb_backup_folder` in `secureboot`) |

Each play loads only what it needs via `vars_files`. The LLM DispVM play also loads `vars/sys_gpu.yml` for GPU PCI IDs. The OCR DVM and networking plays also load `vars/llm.yml` for `llm_tcp_port` and `llm_dispvm`.

### Host Variables Convention

Variables used in `hosts:` patterns are prefixed with `host_`:

```
host_<feature>_<descriptor>
```

Examples: `host_llm_template`, `host_llm_dvm`, `host_llm_claude_code`, `host_ocr_template`, `host_ocr_dvm`, `host_ocr_data`, `host_sys_gpu_template`, `host_messenging_template`, `host_messenging_vm`.

The `ansible-playbook.sh` wrapper greps for this prefix, resolves any Jinja2 references, and passes each as `-e var=value`. This is necessary because Ansible resolves `hosts:` before loading `vars_files`.

### VM Provisioning Pattern

Each feature playbook (llm, ocr, sys-gpu) follows this sequence:
1. **Template** — `include_tasks: tasks/clone_template.yml` clones a base template, sets the network, and sets `qrexec_timeout`; then the `_template` role runs inside the VM; finally the network is removed
2. **DVM** — Creates an AppVM with `template_for_dispvms=true`, applies the `_dvm_*` role(s) to configure persistent data (bind dirs, pull models), then shuts down
3. **DispVM** — Creates the final `DispVM` class VM with PCI passthrough, memory/CPU settings
4. **Networking** — Adds `qubes.ConnectTCP` policy entries and configures `qvm-connect-tcp` in client VM's `/rw/config/rc.local`

### Reusable Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `set_prefs` role | `roles/set_prefs/` | Sets any combination of `qrexec_timeout`, `maxmem`, `memory`, `vcpus` on a VM; use via `include_role` with `vars: target_vm: ...` and any of `vm_qrexec_timeout`, `vm_maxmem`, `vm_memory`, `vm_vcpus` — only defined vars are applied |
| `clone_template` tasks | `playbooks/tasks/clone_template.yml` | Clone + set netvm + set timeout; use via `include_tasks` with `vars: clone_src/clone_dest` |

### Roles

| Role | Purpose |
|------|---------|
| `llm_template` | Installs NVIDIA drivers + CUDA, installs Ollama via installer script, configures systemd service with performance env vars |
| `llm_dvm_1` | Configures Qubes bind dirs for `/usr/share/ollama` (persists models across DispVM restarts) |
| `llm_dvm_2` | Pulls Ollama models (gemma4:e4b, gemma4:26b, qwen3:14b, qwen3-vl:8b) and creates custom Modelfile variants with specific context windows |
| `ocr_template` | Installs Python3 + venv tooling |
| `ocr_dvm` | Clones `local-llm-pdf-ocr`, sets up UV venv, copies `.env` config and `start.sh`, wires startup into `rc.local` |
| `sys_gpu_template` | Installs NVIDIA drivers + CUDA (no Ollama) |
| `sys_gpu_dvm` | Empty — DVM needs no additional configuration |
| `base_packages` | Installs `htop` and `tmux` on any Linux VM; uses `ansible_os_family` to select `apt` (Debian) or `dnf` (RedHat); skipped automatically on Windows |
| `secureboot` | Copies sbctl backup/restore scripts to `~/bin`, installs kernel install hook |
| `messenging` | Installs Chrome, Snap, Signal, Whatsie on a Fedora template; creates autostart symlinks in AppVM |

### LLM TCP Connectivity

The LLM service (Ollama, port 11434) runs in `llm-disp` (a DispVM). The `claude-code` AppVM connects to it via Qubes TCP proxy:
- Policy: `qubes.ConnectTCP +11434 claude-code @default allow target=llm-disp`
- Client: `qvm-connect-tcp 11434:@default:11434` in `rc.local`

The OCR service similarly proxies port 11434 from `ocr-disp` → `llm-disp`.

### Conventions

- `when: 0 > 1` marks tasks that are intentionally disabled (keeps YAML structure intact for future re-enablement)
- Tasks that only run on VM creation use `when: <check_var>.rc != 0` (e.g. volume resize, clone)
- Always use fully-qualified collection names (FQCN) for Ansible modules: `ansible.builtin.apt` not `apt`, `ansible.builtin.command` not `command`, `ansible.builtin.lineinfile` not `lineinfile`, etc.
- Never prefix filenames, role names, or task file names with `qubes_` — the entire project is Qubes-specific so the prefix adds no information (e.g. `clone_template.yml` not `qubes_clone_template.yml`, `set_prefs` not `qubes_set_prefs`)

## Keeping README.md up to date

Update `README.md` whenever a change is significant enough that a new user reading
the docs would be misled without it. Specifically, update when you:

- Add, remove, or rename a playbook or role
- Change the VM provisioning pattern or networking topology
- Add or rename inventory groups
- Change how the wrapper script selects variables (the `host_` prefix rule)
- Add new run modes or meaningful new `--tags` / `-e` examples
- Change the testing procedure

Do **not** update README.md for: bug fixes inside a role that don't affect
external behaviour, variable renames that don't change user-facing commands, or
refactors that leave the structure identical from the outside.

## After Making Changes

Always run a syntax check on every modified playbook before considering work done. Outside Dom0 the check will report `qubesos` module errors (the collection is only installed on Dom0) — those are expected and pre-existing; all other errors must be resolved.

```bash
./ansible-playbook.sh playbooks/llm.yml --syntax-check
./ansible-playbook.sh playbooks/ocr.yml --syntax-check
./ansible-playbook.sh playbooks/sys_gpu.yml --syntax-check
./ansible-playbook.sh playbooks/messenging.yml --syntax-check
```

Or for site.yml when it covers the changed area:

```bash
./ansible-playbook.sh site.yml --tags llm --syntax-check
```
