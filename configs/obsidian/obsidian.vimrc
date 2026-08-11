" Obsidian vim mode, ported from configs/nvim/lua/core/{options,keymaps}.lua.
"
" Read by the obsidian-vimrc-support plugin, which is the only way to configure
" Obsidian's vim mode. Obsidian runs CodeMirror 6 vim (@replit/codemirror-vim),
" not Neovim, so this file is a subset of the Neovim config rather than a copy.
"
" Two hard limits shape what is here:
"
"   1. CodeMirror vim defines exactly five `:set` options - filetype, textwidth,
"      langmap, pcre and insertModeEscKeysTimeout - and the plugin adds two more,
"      clipboard and tabstop. Any other name raises "Unknown option" on load and
"      stops the rest of the file. Everything below the `set` block is a mapping.
"   2. There is no `mapleader`, so Space is written out as <Space> each time.
"
" Failed `obcommand` lines are silent. Every command id used here was checked
" against obsidian.asar before being written down.
"
" Neovim options with no vim-mode equivalent, and where Obsidian sets them:
"   number, relativenumber -> Settings > Editor > Show line numbers, plus the
"                             obsidian-relative-line-numbers community plugin
"   wrap, linebreak        -> Settings > Editor > Readable line length
"   shiftwidth, expandtab  -> Settings > Editor > Indent using spaces, Tab size
"   conceallevel = 0       -> Settings > Editor > Strict line breaks / live
"                             preview; Obsidian conceals markdown by design
"   scrolloff, cursorline,
"   splitbelow, splitright,
"   undofile, showmode     -> not configurable
" ignorecase and smartcase need no line: CodeMirror vim hardcodes both on.

set clipboard=unnamed
set tabstop=4


" --- Ex commands for the Obsidian side -------------------------------------

exmap back obcommand app:go-back
exmap forward obcommand app:go-forward

exmap tabnext obcommand workspace:next-tab
exmap tabprev obcommand workspace:previous-tab
exmap tabnew obcommand workspace:new-tab
exmap paneclose obcommand workspace:close
exmap splitvertical obcommand workspace:split-vertical
exmap splithorizontal obcommand workspace:split-horizontal

exmap focusleft obcommand editor:focus-left
exmap focusright obcommand editor:focus-right
exmap focusup obcommand editor:focus-top
exmap focusdown obcommand editor:focus-bottom

exmap savefile obcommand editor:save-file
exmap togglecomment obcommand editor:toggle-comment
exmap togglefold obcommand editor:toggle-fold
exmap foldall obcommand editor:fold-all
exmap unfoldall obcommand editor:unfold-all
exmap followlink obcommand editor:follow-link
exmap togglesource obcommand editor:toggle-source
exmap togglereadable obcommand editor:toggle-readable-line-length
exmap swaplineup obcommand editor:swap-line-up
exmap swaplinedown obcommand editor:swap-line-down

exmap explorer obcommand file-explorer:open
exmap quickswitch obcommand switcher:open
exmap globalsearch obcommand global-search:open
exmap palette obcommand command-palette:open
exmap outline obcommand outline:open
exmap backlinks obcommand backlink:open


" --- Register hygiene (keymaps.lua) ----------------------------------------

" delete single character without copying into register
nnoremap x "_x

" keep last yanked when pasting over a selection
vnoremap p "_dP


" --- Scrolling and search, centred (keymaps.lua) ----------------------------

" CodeMirror vim has no `zz`, so these use `z.` - same recentre, but it also
" moves to the first non-blank character of the line.
nnoremap <C-d> <C-d>z.
nnoremap <C-u> <C-u>z.
nnoremap n nz.
nnoremap N Nz.


" --- Stay in indent mode (keymaps.lua) --------------------------------------

vnoremap < <gv
vnoremap > >gv


" --- Tabs stand in for buffers and splits (keymaps.lua) ---------------------

" Obsidian has one pane concept where Neovim has buffers, splits and tabs, so
" <Tab>/<S-Tab> cycling and the <Space>t* family both land on Obsidian tabs.
nmap <Tab> :tabnext<CR>
nmap <S-Tab> :tabprev<CR>
nmap <Space>bq :paneclose<CR>
nmap <Space>bo :tabnew<CR>

nmap <Space>to :tabnew<CR>
nmap <Space>tq :paneclose<CR>
nmap <Space>tn :tabnext<CR>
nmap <Space>tp :tabprev<CR>


" --- Window management (keymaps.lua) ---------------------------------------

nmap <Space>v :splitvertical<CR>
nmap <Space>h :splithorizontal<CR>
nmap <Space>sq :paneclose<CR>

" <C-h/j/k/l> across splits, matching what herdr.nvim binds in Neovim.
nmap <C-h> :focusleft<CR>
nmap <C-l> :focusright<CR>
nmap <C-k> :focusup<CR>
nmap <C-j> :focusdown<CR>


" --- Files, search and pickers (plugins/fzf.lua, plugins/snacks.lua) --------

nmap <Space>e :explorer<CR>
nmap <Space>sf :quickswitch<CR>
nmap <Space>sg :globalsearch<CR>
nmap <Space>ss :palette<CR>
nmap <Space><Space> :quickswitch<CR>
nmap <Space>so :outline<CR>
nmap <Space>sb :backlinks<CR>


" --- Editing (keymaps.lua, plugins/comment.lua, plugins/mini.lua) ----------

nmap <Space>sn :savefile<CR>
nmap <Space>lw :togglereadable<CR>

" plugins/comment.lua binds <C-/>; Obsidian's own hotkey already covers that
" chord, so the vim-side binding is the gc family.
nmap gcc :togglecomment<CR>
vmap gc :togglecomment<CR>

" mini.move: alt-j/k slide the current line, same as in Neovim.
nmap <A-j> :swaplinedown<CR>
nmap <A-k> :swaplineup<CR>

" folds
nmap za :togglefold<CR>
nmap zM :foldall<CR>
nmap zR :unfoldall<CR>

" gd follows a link, the closest thing Obsidian has to a definition jump.
" gf is provided by the plugin already, and [[ / ]] jump between headings.
nmap gd :followlink<CR>
nmap <C-o> :back<CR>
nmap <C-i> :forward<CR>


" --- mini.surround ----------------------------------------------------------

" The plugin's `surround` ex command takes the two wrapping strings, so each
" delimiter needs its own binding rather than mini's prompt. `sa` in visual
" mode is mini.surround's own add key, and `sa*` / `sa`` land on the same
" delimiters there as here.
exmap surround_italic surround * *
exmap surround_code surround ` `
exmap surround_bold surround ** **
exmap surround_highlight surround == ==
exmap surround_wiki surround [[ ]]

vmap sa* :surround_italic<CR>
vmap sa` :surround_code<CR>
vmap sab :surround_bold<CR>
vmap sah :surround_highlight<CR>
vmap saw :surround_wiki<CR>
