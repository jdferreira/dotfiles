#!/usr/bin/env bash

mkdir -p "$HOME/.bin"

# Copy the executables in the bin/ directory into the $HOME's .bin/ directory
# This is automatically added to the $PATH with the installed `.bashrc` file.
cp -a ./bin/. "$HOME/.bin/"
