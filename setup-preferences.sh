#!/bin/env bash

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

    cp -rl preferences/vscode/.vscode/* "$HOME/.vscode"
    cp -rl preferences/vscode/user-config/* "$HOME/.config/Code/User"
fi
