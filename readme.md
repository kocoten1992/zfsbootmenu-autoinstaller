# ZFS Boot Menu Install Script

## How to run

`wget -qO- https://raw.githubusercontent.com/username/repo/branch/path/to/script.sh | bash`



## Other random Notes

### Ansible setup
[Ansible Docs](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

- Install ansible: `pipx install --include-deps ansible`
- Install ansible community for chroot stuff: `ansible-galaxy collection install community.general`

- Testing
    - `ansible-playbook --check setup-zfsbootmenu.yml -i inventory.yml`
