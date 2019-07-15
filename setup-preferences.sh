#!/usr/bin/env bash

wants() {
    echo -n "Do you want to install preferences for $1? [y/N] "
    read ans
    [ "$ans" = "y" -o "$ans" = "Y" ]
}

if wants 'gnome-terminal'; then
    dconf load /org/gnome/terminal/ < preferences/gnome-terminal/config
fi

if wants 'VS Code'; then
    mkdir -p "$HOME/.vscode"
    mkdir -p "$HOME/.config/Code/User"

    unzip -oq -d "$HOME/.vscode" preferences/vscode/vscode.zip
    unzip -oq -d "$HOME/.config/Code/User" preferences/vscode/user-config.zip
fi
