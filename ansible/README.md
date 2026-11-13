# Ansible lab (roadmap module D10, optional)

Idempotent configuration of two managed nodes. The nodes are `ubuntu:24.04` containers
(pinned by digest) reached with the `community.docker.docker` connection plugin, so no SSH
keys or VMs are needed.

```
ansible/
├── ansible.cfg                  inventory, collection and role paths
├── requirements.txt             control node: ansible-core 2.20.11, docker SDK 7.2.0
├── collections/requirements.yml community.docker 5.4.0
├── inventory/lab.yml            group lab_nodes = node1, node2 (docker connection)
├── inventory/host_vars/node2.yml per-host override (environment, replicas)
├── site.yml                     3 plays: create nodes -> bootstrap python (raw) -> baseline role
└── roles/baseline/              packages, group/user, directories, template, logrotate, handler
```

## Run (inside the devops-lab WSL distro)

```bash
python3 -m venv ~/work/ansible-venv
~/work/ansible-venv/bin/pip install -r ansible/requirements.txt
cd ansible
export PATH="$HOME/work/ansible-venv/bin:$PATH"
export ANSIBLE_CONFIG="$PWD/ansible.cfg"   # required on /mnt/<drive>: see below
ansible-galaxy collection install -r collections/requirements.yml -p ./collections
ansible-playbook site.yml                  # first run: changed > 0
ansible-playbook site.yml                  # second run: changed=0 (idempotent)
ansible-playbook site.yml --check --diff   # report drift without changing anything
```

Why `ANSIBLE_CONFIG`: the repository lives on a Windows drive mounted with drvfs, where every
directory looks world-writable. Ansible refuses to load `ansible.cfg` from a world-writable
current directory, because anyone could plant one. Naming the file explicitly is the
documented way around it. Moving the project to a native Linux path also works.

Clean up: `docker rm -f node1 node2`.
