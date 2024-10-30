#!/usr/bin/bash

apt install python3 -y
apt install pipx - y
pipx install --include-deps ansible
pipx ensurepath
source ~/.bashrc
