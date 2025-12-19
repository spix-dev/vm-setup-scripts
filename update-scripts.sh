#!/usr/bin/env bash

if ! command -v git &> /dev/null; then
    echo "Git not found. Installing git..."
    sudo apt-get update
    sudo apt-get install -y git
fi

git clone https://github.com/spix-dev/vm-setup-scripts.git
cd vm-setup-scripts
chmod +x *.sh

echo "Scripts downloaded successfully!"
