" Always show line numbers
set number

" Set 4 spaces as indentation
filetype plugin indent on
set tabstop=4
set shiftwidth=4
set expandtab

" Set spell check in git commit messages
autocmd Filetype gitcommit setlocal spell
