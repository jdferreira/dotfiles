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
