#!/bin/env bash

wants() {
    echo -n "Do you want to install $1? [y/N] "
    read ans
    [ "$ans" = "y" -o "$ans" = "Y" ]
}

sudo apt update
sudo apt install git vim curl

if wants 'VS Code'; then
    echo 'Go to https://code.visualstudio.com/Download and download the'
    echo 'VS Code .deb file. Save it into the ~/Downloads directory.'
    echo 'When ready, press ENTER'
    read
    sudo apt install ./Downloads/code*.deb
fi

if wants 'Docker'; then
    sudo apt install docker-ce
fi

if wants 'pyenv'; then
    curl https://pyenv.run | bash
    
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
    pyenv shell $(pyenv versions | tail -n1) 2> /dev/null
fi

if wants 'git-remote-dropbox'; then
    pip install git-remote-dropbox
fi
