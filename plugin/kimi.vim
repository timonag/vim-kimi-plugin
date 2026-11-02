" Guard against being sourced twice (e.g. when Vundle reloads plugins).
if exists('g:loaded_kimi_plugin')
  finish
endif
let g:loaded_kimi_plugin = 1

" This plugin has no configuration: every behaviour that used to be a
" g:kimi_* setting now has one built-in value, documented in doc/kimi.txt.

" ── commands ─────────────────────────────────────────────────────────────────

command! KimiOpen    call kimi#open()
command! KimiToggle  call kimi#toggle()
command! KimiClose   call kimi#close()
command! KimiExplain call kimi#explain('n')
command! KimiModel   call kimi#select_model()
command! KimiResume  call kimi#resume()
command! KimiInput   call kimi#input#open()

" Session panel.
command!          KimiSessions      call kimi#panel#toggle()
command!          KimiSessionsOpen  call kimi#panel#open()
command!          KimiSessionsClose call kimi#panel#close()
command! -nargs=? KimiNew           call kimi#new(<q-args>)
command! -nargs=? KimiRename        call kimi#rename(<q-args>)

" Workspaces: the git worktrees sessions run in.
command! KimiWorkspaces call kimi#workspace#pick()

" Git diff tree.
" The whole sidebar column: sessions, diff tree and NERDTree together.
command! KimiSidebars call kimi#sidebar#toggle_all()

command! KimiDiff        call kimi#difftree#toggle()
command! KimiDiffOpen    call kimi#difftree#open()
command! KimiDiffClose   call kimi#difftree#close()
command! KimiDiffRefresh call kimi#difftree#refresh()
" Sets the base for one branch: the argument's, or the one under the cursor.
" An empty argument clears that branch's override.
command! -nargs=* -complete=customlist,kimi#difftree#complete_branch
      \ KimiDiffBase call kimi#difftree#base_command(<q-args>)

" Window navigation commands (wrappers around wincmd h/l/k/j).
command! KimiFocus    call kimi#focus()
command! KimiWinLeft  call kimi#win_move('h')
command! KimiWinRight call kimi#win_move('l')
command! KimiWinUp    call kimi#win_move('k')
command! KimiWinDown  call kimi#win_move('j')

" ── autocommands ─────────────────────────────────────────────────────────────

augroup kimi_plugin
  autocmd!
  " Vim refuses to exit while a terminal job is running (E947), so the jobs
  " must be stopped before that check runs. ExitPre fires just after QuitPre
  " but only for a :q / :wq / :qall that actually ends the session, so a live
  " session survives closing an ordinary split. QuitPre must not be used here:
  " it fires for every window close and would kill the session each time.
  if exists('##ExitPre')
    autocmd ExitPre * call kimi#_stop_jobs()
  else
    " Vim 8.1 before patch 8.1.0446 has no ExitPre; fall back to QuitPre with
    " a guard so only the quit that closes the last window stops the jobs.
    autocmd QuitPre * call kimi#_quit_pre()
  endif
  " VimLeavePre fires after Vim commits to exiting; wipe the buffers then.
  autocmd VimLeavePre * call kimi#close_all()
  " Track the most recently focused session, so the picker offers it first.
  autocmd WinEnter * call kimi#_win_enter()
  " Share one column with NERDTree: re-stack when it opens, and let the panel
  " reclaim the column when it closes. Both hooks no-op without NERDTree.
  " FileType fires while NERDTree is still building itself, long before
  " NERDTreeInit, so the repair lands before the two columns are painted.
  " NERDTreeInit is kept as a second chance for trees that skip that path.
  autocmd FileType nerdtree call kimi#panel#_nerdtree_init()
  " NERDTree's highlight groups only exist once its syntax file has been
  " sourced, so pick them up the first time a tree appears.
  autocmd FileType nerdtree call kimi#panel#_relink()
  autocmd FileType nerdtree call kimi#difftree#_relink()
  " A save is the one event that reliably changes the uncommitted set.
  autocmd BufWritePost * call kimi#difftree#_on_write()
  autocmd User NERDTreeInit call kimi#panel#_nerdtree_init()
  if exists('##WinClosed')
    autocmd WinClosed * call kimi#panel#_win_closed(expand('<amatch>'))
  endif
augroup END

" ── keymaps ──────────────────────────────────────────────────────────────────

nnoremap <silent> <leader>ko :KimiOpen<CR>
nnoremap <silent> <leader>kt :KimiToggle<CR>
nnoremap <silent> <leader>kx :KimiClose<CR>
nnoremap <silent> <leader>kf :KimiFocus<CR>

" Start a session even when others are running. <leader>ko focuses or picks
" one instead, and only creates when nothing is live.
nnoremap <silent> <leader>kn :KimiNew<CR>

" Toggle the session panel.
nnoremap <silent> <leader>ks :KimiSessions<CR>

" Toggle the git diff tree.
nnoremap <silent> <leader>kd :KimiDiff<CR>

" Pick the workspace to work in; NERDTree follows the choice.
nnoremap <silent> <leader>kw :KimiWorkspaces<CR>

" Raise or dismiss the whole sidebar column. Normal mode only: <C-a> must
" keep incrementing a number under the cursor elsewhere (insert mode,
" visual mode, etc).
nnoremap <silent> <C-a> :KimiSidebars<CR>

" Explain: normal mode sends the whole file; visual mode sends the selection.
nnoremap <silent> <leader>ke :KimiExplain<CR>
xnoremap <silent> <leader>ke :<C-u>call kimi#explain('v')<CR>

" Switch model for the current session (hands over to kimi's own picker).
nnoremap <silent> <leader>km :KimiModel<CR>

" Resume a previous session from the last 10 for this directory.
nnoremap <silent> <leader>kr :KimiResume<CR>

" Floating input window for composing multi-line messages.
nnoremap <silent> <leader>ki :KimiInput<CR>

" Window navigation (mirrors Ctrl-W hjkl as leader shortcuts).
nnoremap <silent> <leader>kh :KimiWinLeft<CR>
nnoremap <silent> <leader>kl :KimiWinRight<CR>
nnoremap <silent> <leader>kk :KimiWinUp<CR>
nnoremap <silent> <leader>kj :KimiWinDown<CR>
