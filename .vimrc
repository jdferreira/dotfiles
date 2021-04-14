" Always show line numbers
set number

" Set 4 spaces as indentation
filetype plugin indent on
set tabstop=4
set shiftwidth=4
set expandtab

" Set spell check in git commit messages
autocmd Filetype gitcommit setlocal spell

" Command to wrap lines without splitting in between words
command! -nargs=* Wrap set wrap linebreak nolist

" Shift+Up and Shift+Down move one line up or down, without moving the cursor
map <S-Down> <C-E>
map <S-Up>   <C-Y>
