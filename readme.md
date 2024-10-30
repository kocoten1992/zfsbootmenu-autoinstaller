# Ansible Playbook for installing zfsbootmenu on Debian

## Stuff I did while testing stuff out

### Ansible setup
[Ansible Docs](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

- Install ansible: `pipx install --include-deps ansible`
- Install ansible community for chroot stuff: `ansible-galaxy collection install community.general`

- Testing
    - `ansible-playbook --check setup-zfsbootmenu.yml -i inventory.yml`