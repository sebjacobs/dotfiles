let mapleader=","                 " Make , the leader key

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" CONFIGURE VUNDLE
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

Plugin 'gmarik/Vundle.vim'

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" VUNDLE PLUGINS
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

Plugin 'scrooloose/nerdtree'
Plugin 'kien/ctrlp.vim'
Plugin 'nanotech/jellybeans.vim'
Plugin 'tpope/vim-fugitive'
Plugin 'scrooloose/nerdcommenter'
Plugin 'mileszs/ack.vim'
Plugin 'tpope/vim-surround'
Plugin 'tpope/vim-rails'
Plugin 'myusuf3/numbers.vim'
Plugin 'bling/vim-airline'
Plugin 'ervandew/supertab'
Plugin 'tpope/vim-endwise'
Plugin 'tpope/vim-haml'
Plugin 'skalnik/vim-vroom'
Plugin 'vim-ruby/vim-ruby'
Plugin 'rking/ag.vim'

call vundle#end()

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" SENSIBLE DEFAULTS, MOSTLY COMING FROM JANUS
" https://github.com/carlhuda/janus/blob/master/janus/vim/core/before/plugin/settings.vim
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

set nocompatible                  " Vim, not vi
set number                        " Show line numbers
set ruler                         " Display line and column number

syntax enable                     " Enable syntax highlighting
set encoding=utf-8                " Use UTF-8 by default
set backspace=indent,eol,start  " Backspace through everything

set nowrap                        " Don't wrap long lines
set tabstop=2                     " A tab is two spaces long
set shiftwidth=2                  " Auto-indent using 2 spaces
set expandtab                     " Use spaces instead of tabs
set smarttab                      " Backspace deletes whole tabs at the beginning of a line
set sts=2                         " Backspace deletes whole tabs at the end of a line
set list                          " Show invisible characters

set listchars=""                  " Reset listchars
set listchars=tab:\ \             " Display a tab as "  "
set listchars+=trail:.            " Display trailing whitespace as "."
set listchars+=extends:>          " Show ">" at the end of a wrapping line
set listchars+=precedes:<         " Show "<" at the beginning of a wrapping line

set hlsearch                      " Highlight search matches
set incsearch                     " Enable incremental searching
set ignorecase                    " Make searches case insensitive
set smartcase                     " (Unless they contain a capital letter)

set wildmenu                      " Sensible, powerful tab completion
set wildmode=list:longest,full    "

""""""""""""""""""""""
" FILE TYPES TO IGNORE
""""""""""""""""""""""

set wildignore+=*.o,*.out,*.obj,.git,*.rbc,*.rbo,*.class,.svn,*.gem
set wildignore+=*.zip,*.tar.gz,*.tar.bz2,*.rar,*.tar.xz
set wildignore+=*/public/assets/*,/vendor/gems/*,*/vendor/cache/*,*/.bundle/*,*/.sass-cache/*,*/tmp/*
set wildignore+=*/public/uploads/*,*/log/*
set wildignore+=*/.git/*,*/.rbx/*,*/.hg/*,*/.svn/*,*/.DS_Store
set wildignore+=*.swp,*~,._*

""""""""""""""""""""""""""""""""""""
" WHERE TO PUT BACKUP AND SWAP FILES
""""""""""""""""""""""""""""""""""""

set backupdir=~/.vim/_backup//
set directory=~/.vim/_temp//

"""""""""""""""""""""""""""""""""""""""
" SET FILE TYPES FOR VARIOUS EXTENSIONS
"""""""""""""""""""""""""""""""""""""""

filetype on                       " Enable filetype detection
filetype indent on                " Enable filetype-specific indenting
filetype plugin on                " Enable filetype-specific plugins

function! s:setupWrapping()
  set wrap
  set linebreak
  set textwidth=72
  set nolist
endfunction

au BufRead,BufNewFile {Capfile,Gemfile,Rakefile,Vagrantfile,Thorfile,Procfile,*.ru,*.rake,*.rabl} set ft=ruby
au BufRead,BufNewFile *.{md,markdown,mdown,mkd,mkdn,txt} set ft=markdown | call s:setupWrapping()
au BufRead,BufNewFile *.json set ft=javascript
au BufRead,BufNewFile *.scss set filetype=scss


" Remember last location in a file, unless it's a git commit message
au BufReadPost * if &filetype !~ '^git\c' && line("'\"") > 0 && line("'\"") <= line("$")
  \| exe "normal! g`\"" | endif

""""""""""
" MAPPINGS
""""""""""

" Make :W do the same as :w
command! W :w

" Hit return to clear search highlighting
noremap <cr> :nohlsearch<cr>

" Move around splits with Ctrl + HJKL
noremap <c-j> <c-w>j
noremap <c-k> <c-w>k
noremap <c-h> <c-w>h
noremap <c-l> <c-w>l

" Ctrl + L outputs a hashrocket in insert mode
imap <c-l> <space>=><space>

" <leader>= resizes all windows
map <leader>= <c-w>=

cnoremap %% <c-r>=expand('%:h').'/'<cr>

" <leader>e edits a file in the current path
map <leader>e :edit %%

" <leader>g opens the Git status window
map <leader>g :Gstatus<cr>

" Use F9 to toggle between paste and nopaste
set pastetoggle=<F9>

"""""""""
" COLOURS
"""""""""

set t_Co=256            " Use all 256 colours
set background=dark     " Dark terminal background
color jellybeans        " Use the jellybeans colour theme

""""""""""""""""""""
" MISC CONFIGURATION
""""""""""""""""""""

set shell=/bin/bash     " Make Vim load bash environment (e.g. RVM)
set timeoutlen=500      " Only wait 500ms before processing certain commands
set showcmd             " Display incomplete commands
set scrolloff=3         " Keep more lines when scrolling off the end of a buffer
set laststatus=2        " Show the statusline

" Set statusline to something sensible
" filename [encoding,line-endings][filetype] ... col,row/total-rows Position
set statusline=%f\ [%{strlen(&fenc)?&fenc:'none'},%{&ff}]%y%h%m%r%=%c,%l/%L\ %P

"""""""""""""""""""""""
" CTRLP CUSTOM SETTINGS
"""""""""""""""""""""""

" Set up a bunch of <leader> key mappings for common Ruby/Rails directories
map <leader>gv :CtrlP app/views<cr>
map <leader>gc :CtrlP app/controllers<cr>
map <leader>gm :CtrlP app/models<cr>
map <leader>gh :CtrlP app/helpers<cr>
map <leader>gl :CtrlP lib<cr>
map <leader>gp :CtrlP public<cr>
map <leader>f :CtrlP<cr>
map <leader>F :CtrlP %%<cr>

let g:ctrlp_show_hidden = 1

" List files from top to bottom in CtrlP
let g:ctrlp_match_window_reversed = 0

" Set the maximum height of the match window:
let g:ctrlp_max_height = 30

" CtrlP shouldn't manage the current directory
let g:ctrlp_working_path_mode = 0

" Keep cache between sessions
let g:ctrlp_clear_cache_on_exit = 0

"""""""""""""""""""
" NERDTREE MAPPINGS
"""""""""""""""""""

let NERDTreeShowHidden=1

" <leader>N to open and close NERDTree
map <leader>N :NERDTreeToggle<cr>

"""""""""""""""""""
" VROOM MAPPINGS
"""""""""""""""""""
map <leader>t :VroomRunTestFile<cr>
map <leader>T :VroomRunNearestTest<cr>

"""""""""""""""""""
" RAILS MAPPINGS
"""""""""""""""""""
nnoremap <leader>. :A<cr>

""""""""""""""""""""""""""""""""""""""""
" STRIP TRAILING WHITESPACE ON FILE SAVE
""""""""""""""""""""""""""""""""""""""""

function! <SID>StripTrailingWhitespaces()
    " Preparation: save last search, and cursor position.
    let _s=@/
    let l = line(".")
    let c = col(".")
    " Do the business:
    %s/\s\+$//e
    " Clean up: restore previous search history, and cursor position
    let @/=_s
    call cursor(l, c)
endfunction
autocmd BufWritePre * :call <SID>StripTrailingWhitespaces()

""""""""""""""""""""""""""""""""""""""
" RENAME CURRENT FILE (GARY BERNHARDT)
""""""""""""""""""""""""""""""""""""""

function! RenameFile()
    let old_name = expand('%')
    let new_name = input('New file name: ', expand('%'))
    if new_name != '' && new_name != old_name
        exec ':saveas ' . new_name
        exec ':silent !rm ' . old_name
        redraw!
    endif
endfunction
map <leader>n :call RenameFile()<cr>

autocmd filetype make setlocal noexpandtab
