#!/bin/env bash

wants() {
    echo -n "Do you want to store preferences for $1? [y/N] "
    read ans
    [ "$ans" = "y" -o "$ans" = "Y" ]
}

if wants 'gnome-terminal'; then
    mkdir -p preferences/gnome-terminal

    dconf dump /org/gnome/terminal/ > preferences/gnome-terminal/config
fi

if wants 'VS Code'; then
    mkdir -p preferences/vscode

    # Create a ZIP file with the contents of ~/.vscode
    (
        rm -f preferences/vscode/vscode.zip
        cd "$HOME/.vscode"
        \ls -A | \
            tr '\n' '\0' | \
            xargs -0 zip -qr "$OLDPWD"/preferences/vscode/vscode.zip
    )

    # Create a ZIP file with the interesting contents of ~/.config/Code/User
    (
        rm -f preferences/vscode/user-config.zip
        cd "$HOME/.config/Code/User"

        # Find all user cofnig files that are not storage
        # and add them to a ZIP file
        \ls -A | \
            grep -vP 'Storage$' | \
            tr '\n' '\0' | \
            xargs -0 zip -qr "$OLDPWD"/preferences/vscode/user-config.zip
    )
fi
