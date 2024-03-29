#!/usr/bin/env bash

wants() {
    echo -n "Do you want to install $1? [y/N] "
    read ans
    [ "$ans" = "y" -o "$ans" = "Y" ]
}

sudo apt update
sudo apt install git vim curl htop dwdiff fonts-firacode rclone colordiff tree

if wants 'Vector Mono'; then
    mkdir -p "$HOME/.fonts"

    curl 'https://github.com/rubjo/victor-mono/raw/master/public/VictorMonoAll.zip' > /tmp/victor.zip

    unzip -j -d "$HOME/.fonts" /tmp/victor.zip 'OTF/*'
fi

if wants 'VS Code'; then
    echo 'Go to https://code.visualstudio.com/Download and download the'
    echo 'VS Code .deb file. Save it into the ~/Downloads directory.'
    echo 'When ready, press ENTER'
    read
    sudo apt install ./Downloads/code*.deb
fi

if wants 'Docker'; then
    echo 'Described in https://docs.docker.com/install/linux/docker-ce/ubuntu/'

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
         $(lsb_release -cs) \
         stable\
        "

    sudo apt update
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

if wants 'pygments'; then
    pip install pygments
fi

# List of installed packages that are "interesting"
# `pass` (needs `haveged`) --> I do not understand how to share the gpg key yet...
# `strongswan` (for VPN@ciencias)
