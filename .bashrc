########################
# Initial quick checks #
########################

# If not running interactively, don't do anything
case $- in
    *i*) ;;
    *) return;;
esac


#####################
# PS1 customization #
#####################

get_short_wd() {
    local depth=3
    local ellipsis="…"
    local cwd="${PWD/#$HOME/\~}"

    if [ $(echo -n $cwd | awk -F '/' '{ print NF }') -gt $depth ]; then
        tail=$(seq $(($depth-2)) '-1' 0 | sed 's/.*/$(NF-\0)/' | paste -sd '/' - | sed 's_/_ "/" _g')

        cwd=$(echo -n $cwd | awk -F '/' '{ print $1 "/" "'"$ellipsis"'" "/" '"$tail"' }')
    fi

    echo $cwd
}

parse_git_branch() {
    local yellow="$(tput setaf 3)$(tput bold)"
    local reset="$(tput sgr0)"

    git symbolic-ref HEAD --short 2> /dev/null | sed -e 's/.*/('"$yellow"'\0'"$reset"')/'
}

PS1='\[\e[32m\]\t\[\e[00m\] \
[\[\e[31m\]\h\[\e[00m\]] \
\[\e[34m\]$(get_short_wd)\[\e[00m\] \
$(parse_git_branch)\n\
\$ '


#########################
# History configuration #
#########################

# Ignore duplicate lines and lines starting with a space in the history
HISTCONTROL='ignoreboth'

# Ignore `fg`, `bg` and `exit` commands
HISTIGNORE='bg:fg:exit'

# Don't limit the number of saved commands
HISTSIZE=''

# Set a nice timestamp format
export HISTTIMEFORMAT='%d/%m/%y %T '

# Append to the history file, don't overwrite it
shopt -s histappend


##################
# Autocompletion #
##################

# Enable programmable completion features
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi


##########################################################
# Miscellaneous stuff regarding the terminal's behaviour #
##########################################################

# Check the window size after each command and, if necessary, update the
# values of LINES and COLUMNS.
shopt -s checkwinsize

# The pattern '**' used in a pathname expansion context will match all files
# and zero or more directories and subdirectories.
shopt -s globstar


######################################
# Edit systemd config files with vim #
######################################

export SYSTEMD_EDITOR="vim"

###########
# Aliases #
###########

# Enable color support for various default commands
alias ls='ls --color=always'
alias grep='grep --color=always'

# Other aliases
alias ll='ls -l'

# To show word-wide differences. This needs dwdiff
if which dwdiff > /dev/null; then
    alias wdiffless="dwdiff -P -w $'\033[1;37;41m' -x $'\033[0m' -y $'\033[1;37;42m' -z $'\033[0m'"
fi

# Add an 'alert' alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Echo the apt logs
alias apt-log='zcat -qf /var/log/apt/history.log*'

# Use pygmentize to color code on the terminal
alias pyg='pygmentize -O style=native'

# Format JSON output
alias ppjson='python -m json.tool --sort-keys | pyg -l json'

alias jn='jupyter notebook'
alias jl='jupyter lab'

# Start nautilus, ensuring that the executable starts if it has not yet been
# started before
nautilus() {
    local dest="${1:-.}"
    (command nautilus "$dest" >/dev/null 2>&1 & disown)
}

########
# Less #
########

# Make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Do not chop long lines, and interpret color codes
export LESS='-SR'


#########
# Pyenv #
#########

if [ -d "$HOME/.pyenv/bin" ]; then
    export PATH="$HOME/.pyenv/bin:$PATH"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
    pyenv shell $(pyenv versions | tail -n1) 2>/dev/null
fi


########
# NLTK #
########

export NLTK_DATA="$HOME/.nltk_data"

############
# Composer #
############

if [ -d "$HOME/.config/composer/vendor/bin" ]; then
    PATH="$HOME/.config/composer/vendor/bin:$PATH"
fi


#######
# nvm #
#######

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


###########################
# Docker & Docker compose #
###########################

upsearch() {
    if [ "$PWD" != '/' ]; then
        if [ -e "$1" ]; then
            echo "$PWD/$1"
        else
            ( cd .. && upsearch "$1" )
        fi
    fi
}

dc() {
    local up
    up=$(upsearch docker-compose.yml)
    if [ "$up" = '' ]; then up=$(upsearch docker-compose.yaml); fi
    if [ "$up" = '' ]; then echo 'Cannot find docker-compose.yml' >&2; return; fi

    (
        cd "$(dirname "$up")"
        docker-compose exec "$@"
    )
}


############################
# Docker specific commands #
############################

alias composer='docker run --rm -it -v "$(pwd):/app" -v "$HOME/.composer:/tmp" -u "$(id -u):$(id -g)" composer'

########################
# Personal executables #
########################

PATH="$HOME/.bin:$PATH"

################
# Google cloud #
################

if [ -d "$HOME/.google-cloud-sdk" ]; then
    # Update PATH
    source "$HOME/.google-cloud-sdk/path.bash.inc"

    # Enable shell command completion
    source "$HOME/.google-cloud-sdk/completion.bash.inc"
fi

################
# Rust & Cargo #
################

if [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/jdferreira/Downloads/google-cloud-sdk-303.0.0-linux-x86_64/google-cloud-sdk/path.bash.inc' ]; then . '/home/jdferreira/Downloads/google-cloud-sdk-303.0.0-linux-x86_64/google-cloud-sdk/path.bash.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/jdferreira/Downloads/google-cloud-sdk-303.0.0-linux-x86_64/google-cloud-sdk/completion.bash.inc' ]; then . '/home/jdferreira/Downloads/google-cloud-sdk-303.0.0-linux-x86_64/google-cloud-sdk/completion.bash.inc'; fi
