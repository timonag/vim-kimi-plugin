" ── kimi.vim core ────────────────────────────────────────────────────────────
"
" Sessions live in a single global registry (autoload/kimi/session.vim), not
" one per tab: several kimi terminals can run side by side. This file is the
" command surface — opening, focusing, closing and sending text — and resolves
" which session a command acts on via kimi#session#target().
"
" Target resolution is asynchronous because popup_menu() is: the commands hand
" a callback to kimi#session#target() rather than returning a session.

" ── public API ───────────────────────────────────────────────────────────────

" Open kimi: focus the current session, ask which one when several are
" running, or start a new one when there are none.
function! kimi#open() abort
  call kimi#session#target('Open kimi session', function('s:focus_id'))
endfunction

" Start a new session regardless of what is already running.
" a:1 name — '' asks for one.
function! kimi#new(...) abort
  call kimi#session#new(a:0 > 0 ? a:1 : '')
endfunction

" Toggle the kimi window: hide it if visible, show it if hidden, open a new
" session if none exists.
function! kimi#toggle() abort
  call kimi#session#target('Toggle kimi session', function('s:toggle_id'))
endfunction

" Move the cursor to a kimi window, revealing or resuming it as needed.
function! kimi#focus() abort
  call kimi#session#target('Focus kimi session', function('s:focus_id'))
endfunction

" End a session: stop the job and wipe its buffer. The conversation stays on
" disk and can be resumed from the panel or :KimiResume.
function! kimi#close() abort
  if empty(kimi#session#live())
    return
  endif
  call kimi#session#target('Close kimi session', function('s:close_id'))
endfunction

" Rename a session. With no argument the new name is prompted for.
function! kimi#rename(...) abort
  if empty(kimi#session#live())
    return
  endif
  let l:name = a:0 > 0 ? a:1 : ''
  call kimi#session#target('Rename which session',
        \ {id -> s:rename_id(id, l:name)})
endfunction

function! s:focus_id(id) abort
  if empty(a:id)
    return
  endif
  let l:rec = kimi#session#get(a:id)
  if empty(l:rec)
    return
  endif

  if kimi#session#status(a:id) ==# 'closed'
    if empty(kimi#session#resume(a:id))
      return
    endif
    let l:rec = kimi#session#get(a:id)
  else
    let l:win = bufwinid(l:rec.bufnr)
    if l:win != -1
      call win_gotoid(l:win)
    else
      " Session alive but not displayed — bring its buffer back into a split.
      execute kimi#split_cmd()
      execute 'buffer ' . l:rec.bufnr
      call kimi#apply_buf_options(a:id)
    endif
  endif

  call kimi#session#touch_focus(a:id)
  call kimi#enter_insert(l:rec.bufnr)
endfunction

function! s:toggle_id(id) abort
  if empty(a:id)
    return
  endif
  let l:rec = kimi#session#get(a:id)
  if empty(l:rec)
    return
  endif
  if l:rec.bufnr != -1 && bufwinid(l:rec.bufnr) != -1
    " Visible — hide it. The buffer stays alive, so the session continues.
    call win_execute(bufwinid(l:rec.bufnr), 'hide')
  else
    call s:focus_id(a:id)
  endif
endfunction

function! s:close_id(id) abort
  if !empty(a:id)
    call kimi#session#delete(a:id)
  endif
endfunction

function! s:rename_id(id, name) abort
  if empty(a:id)
    return
  endif
  let l:name = a:name
  if empty(l:name)
    let l:rec  = kimi#session#get(a:id)
    let l:name = input('Rename to: ', get(l:rec, 'name', ''))
    redraw
  endif
  if !empty(l:name)
    call kimi#session#rename(a:id, l:name)
  endif
endfunction

" ── exit handling ────────────────────────────────────────────────────────────

" Stop every running kimi job without wiping buffers. Called from ExitPre —
" before Vim's E947 check — so :q / :qall can proceed cleanly. VimLeavePre
" then calls close_all() to do the final buffer wipeout.
"
" With many sessions the per-job waits would add up, so the total is capped:
" whatever is still running is left to VimLeavePre.
function! kimi#_stop_jobs() abort
  let l:start = reltime()
  for l:bufnr in kimi#session#bufnrs()
    call kimi#session#stop_job(l:bufnr)
    if str2float(reltimestr(reltime(l:start))) > 2.0
      break
    endif
  endfor
endfunction

" QuitPre fallback for Vim builds without ExitPre (before patch 8.1.0446).
" QuitPre also fires when closing an ordinary split, which must leave every
" session alone, so approximate ExitPre: stop the jobs only when the window
" being quit is the last one that is neither a kimi terminal nor a sidebar.
" Best-effort — with several tabs open QuitPre can't tell :q from :qall.
function! kimi#_quit_pre() abort
  if tabpagenr('$') > 1
    return
  endif
  let l:kimi_bufs  = kimi#session#bufnrs()
  let l:sidebar_bufs = kimi#sidebar#bufnrs()
  let l:others = 0
  for l:winnr in range(1, winnr('$'))
    let l:bufnr = winbufnr(l:winnr)
    " Sidebars are not ordinary windows: a visible NERDTree or panel must not
    " stop a real :q from being recognised as the last one.
    if index(l:kimi_bufs, l:bufnr) == -1
          \ && index(l:sidebar_bufs, l:bufnr) == -1
      let l:others += 1
    endif
  endfor
  if l:others <= 1
    call kimi#_stop_jobs()
  endif
endfunction

" Wipe every kimi terminal buffer. Called from VimLeavePre after the jobs
" have already been stopped by kimi#_stop_jobs() in ExitPre.
function! kimi#close_all() abort
  for l:bufnr in kimi#session#bufnrs()
    call kimi#session#stop_job(l:bufnr)
    silent! execute 'bwipeout! ' . l:bufnr
  endfor
endfunction

" ── window helpers ───────────────────────────────────────────────────────────

" Move the cursor to an adjacent window using standard Vim wincmd directions
" (h=left, l=right, k=up, j=down).
function! kimi#win_move(dir) abort
  execute 'wincmd ' . a:dir
endfunction

" The Ex command that creates the kimi split. botright pins the new window to
" the very right edge of the screen so it doesn't push other splits around.
function! kimi#split_cmd() abort
  return 'botright vertical 80split'
endfunction

" Apply buffer-local options to the current kimi terminal window and tag the
" buffer with its session id, so any window can be mapped back to a record.
function! kimi#apply_buf_options(id) abort
  let b:kimi_session_id = a:id
  setlocal bufhidden=hide   " hide instead of unload on :q, avoiding E947
  setlocal nobuflisted      " hide from buffer list
  setlocal nonumber         " no line numbers
  setlocal norelativenumber
  setlocal signcolumn=no    " no sign column
  setlocal winfixwidth      " prevent the vertical split from being resized
  " In terminal-insert mode Vim surrenders mouse events to the terminal
  " emulator, which handles drag-selection at raw screen coordinates and lets
  " selections cross window borders. Double-Esc enters terminal-normal mode
  " so Vim regains mouse ownership and selection stays within this window.
  " Single Esc is left unbound so it reaches the CLI (interrupt, close popup).
  tnoremap <buffer> <Esc><Esc> <C-\><C-n>
  " The scroll wheel reaches the terminal job in this mode and the CLI
  " ignores it, so wheel-scrolling would be a no-op. Switch to
  " terminal-normal mode and let Vim scroll the scrollback instead; 'i'
  " returns to the CLI.
  tnoremap <buffer> <ScrollWheelUp>   <C-W>N<ScrollWheelUp>
  tnoremap <buffer> <ScrollWheelDown> <C-W>N<ScrollWheelDown>
endfunction

" Enter terminal-insert mode, using feedkeys so the mode switch happens after
" the current command sequence finishes. Guards against feeding 'i' to a
" terminal that is already live (insert mode), which would type into the CLI.
function! kimi#enter_insert(bufnr) abort
  if a:bufnr == -1 || !bufexists(a:bufnr) || !has('terminal')
    return
  endif
  if term_getstatus(a:bufnr) =~# 'normal'
    call feedkeys('i', 'n')
  endif
endfunction

" WinEnter hook: remember which session was most recently focused, so the
" picker can offer the likeliest target first.
function! kimi#_win_enter() abort
  " Remember the last ordinary window, so a file opened from a sidebar lands
  " where the user was actually working.
  call kimi#sidebar#note_focus()
  let l:id = get(b:, 'kimi_session_id', '')
  if !empty(l:id)
    call kimi#session#touch_focus(l:id)
  endif
endfunction

" ── explain ──────────────────────────────────────────────────────────────────

" Send an explain prompt for the current file (mode='n') or the current visual
" selection (mode='v'), to whichever session the user is working in.
function! kimi#explain(mode) abort
  let l:ft = &filetype

  if a:mode ==# 'v'
    let l:lines = s:get_visual_selection()
    let l:desc  = 'the selected text'
  else
    let l:lines = getline(1, '$')
    let l:fname = expand('%:t')
    let l:desc  = empty(l:fname) ? 'this code' : 'the file ' . l:fname
  endif

  " Wrap the code in a fenced code block so kimi gets syntax context.
  let l:fence  = '```' . l:ft
  let l:prompt = 'Explain ' . l:desc . ":\n\n" . l:fence . "\n"
        \ . join(l:lines, "\n") . "\n```"

  call kimi#session#target('Explain in which session',
        \ {id -> s:deliver(id, l:prompt)})
endfunction

" Return the lines covered by the most recent visual selection, trimmed to the
" exact character columns that were selected.
function! s:get_visual_selection() abort
  let [l:l1, l:c1] = getpos("'<")[1:2]
  let [l:l2, l:c2] = getpos("'>")[1:2]
  let l:lines = getline(l:l1, l:l2)
  if empty(l:lines)
    return []
  endif
  " Clamp last and first lines to the selection boundaries.
  let l:lines[-1] = l:lines[-1][:l:c2 - 1]
  let l:lines[0]  = l:lines[0][l:c1 - 1:]
  return l:lines
endfunction

" ── sending ──────────────────────────────────────────────────────────────────

" Send {text} to {id}, resuming it and waiting for startup when necessary.
function! s:deliver(id, text) abort
  if empty(a:id)
    return
  endif
  if kimi#session#status(a:id) ==# 'closed'
    if empty(kimi#session#resume(a:id))
      return
    endif
  endif
  " send_when_ready() returns immediately once the terminal has drawn
  " anything, so an established session is not delayed by the poll.
  call s:send_when_ready(a:id, a:text, 15)
endfunction

" Poll the terminal every 300 ms until output appears (the CLI's startup UI
" is visible), then send {text}. Gives up and sends anyway after {retries}
" tries so the caller is never silently dropped.
function! s:send_when_ready(id, text, retries) abort
  if kimi#session#status(a:id) ==# 'closed'
    return
  endif
  let l:bufnr = kimi#session#get(a:id).bufnr
  if s:terminal_scan(l:bufnr, '\S') || a:retries <= 0
    call s:send(a:id, a:text)
  else
    call timer_start(300, {-> s:send_when_ready(a:id, a:text, a:retries - 1)})
  endif
endfunction

" Scan up to 50 lines of a kimi terminal buffer for lines matching
" {pattern}. Returns true on the first match, false if none found.
function! s:terminal_scan(bufnr, pattern) abort
  if a:bufnr == -1 || !bufexists(a:bufnr)
    return v:false
  endif
  for l:i in range(1, 50)
    if term_getline(a:bufnr, l:i) =~# a:pattern
      return v:true
    endif
  endfor
  return v:false
endfunction

" Send {text} to a session using bracketed-paste escape sequences. Bracketed
" paste tells the CLI's input handler to treat the block as pasted text, so
" embedded newlines don't trigger premature submission.
function! s:send(id, text) abort
  let l:rec = kimi#session#get(a:id)
  if empty(l:rec) || l:rec.bufnr == -1 || !bufexists(l:rec.bufnr)
    return
  endif
  call term_sendkeys(l:rec.bufnr, "\e[200~" . a:text . "\e[201~\r")
  call s:focus_id(a:id)
endfunction

" ── model selection ──────────────────────────────────────────────────────────

" Switch the model a session is running on. Model aliases are user
" configuration (providers and models in the CLI's config.toml), so there is
" no fixed list to offer here: a bare /model hands over to the CLI's own
" picker.
function! kimi#select_model() abort
  call kimi#session#target('Switch model in which session', function('s:choose_model'))
endfunction

function! s:choose_model(id) abort
  if empty(a:id)
    return
  endif
  call s:deliver(a:id, '/model')
endfunction

" ── session resume ───────────────────────────────────────────────────────────

" List the closed sessions known for this directory and reopen the chosen one.
" Names come from the store; sessions never named in Vim fall back to their
" CLI title or last prompt.
function! kimi#resume() abort
  call kimi#session#refresh()
  " all(), not list(): the panel buries the sessions nobody has touched for
  " days, and resuming one is exactly when you want it back. Each is labelled
  " by title or last prompt.
  let l:closed = filter(kimi#session#all(),
        \ {_, r -> r.status ==# 'closed'})

  if empty(l:closed)
    echom 'No previous sessions found for this directory.'
    return
  endif

  let l:menu = ['Resume kimi session:']
  let l:i = 1
  for l:rec in l:closed
    call add(l:menu, printf('%d. %s', l:i, kimi#session#label(l:rec)))
    let l:i += 1
  endfor

  let l:choice = inputlist(l:menu)
  redraw
  if l:choice < 1 || l:choice > len(l:closed)
    return
  endif

  " focus_id() resumes a closed session in the configured split.
  call s:focus_id(l:closed[l:choice - 1].id)
endfunction

" ── common ───────────────────────────────────────────────────────────────────

" Send {text} to the resolved session, opening or resuming one as needed.
function! kimi#_send_input(text) abort
  call kimi#session#target('Send to which session',
        \ {id -> s:deliver(id, a:text)})
endfunction
