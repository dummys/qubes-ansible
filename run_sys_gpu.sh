ansible-playbook -i inventory/hosts.ini -e "sys_gpu_dvm=sys-gpu-dvm" -e "sys_gpu_template=sys-gpu-template"  playbooks/sys-gpu.yml
