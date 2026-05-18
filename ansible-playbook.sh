#!/bin/bash
# Wraps ansible-playbook, auto-injecting all *_host_* variables as -e flags.
#
# Ansible evaluates `hosts:` patterns before loading vars_files, so any variable
# used in a hosts: field must be supplied via -e (extra vars) or inventory.
# This script parses playbooks/vars/*.yml and group_vars/all.yml, resolves simple
# Jinja2 references, and injects matching variables automatically.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

EXTRA_VARS=$(SCRIPT_DIR="$SCRIPT_DIR" python3 << 'PYEOF'
import os, re, sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(1)

script_dir = os.environ['SCRIPT_DIR']
merged = {}

vars_dir = os.path.join(script_dir, 'playbooks', 'vars')
paths = [os.path.join(script_dir, 'playbooks', 'group_vars', 'all.yml')]
if os.path.isdir(vars_dir):
    paths += sorted(
        os.path.join(vars_dir, f)
        for f in os.listdir(vars_dir)
        if f.endswith(('.yml', '.yaml'))
    )

for path in paths:
    if os.path.isfile(path):
        with open(path) as f:
            data = yaml.safe_load(f)
            if isinstance(data, dict):
                merged.update(data)

def resolve(val, ctx, depth=0):
    """Resolve simple {{ varname }} references; stops after 10 levels."""
    if depth > 10 or not isinstance(val, str):
        return str(val)
    prev = None
    while prev != val:
        prev = val
        val = re.sub(
            r'\{\{\s*(\w+)\s*\}\}',
            lambda m: str(ctx.get(m.group(1), m.group(0))),
            val
        )
    return val

for k, v in merged.items():
    if '_host_' in k:
        print(f'-e {k}={resolve(str(v), merged)}')
PYEOF
)

exec ansible-playbook $EXTRA_VARS "$@"
