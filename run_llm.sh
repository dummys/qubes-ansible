ansible-playbook -i inventory/hosts.ini -e "llm_dvm=llm-dvm" -e "llm_template=llm-template-debian-13-xfce" -e "claude_code_vm=claude-code" playbooks/llm.yml
