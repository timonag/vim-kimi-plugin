" ── the Kimi Code CLI ────────────────────────────────────────────────────────
"
" Everything this plugin knows about the CLI it drives: how to launch it,
" where it keeps its sessions, and what its terminal says while it works.
" Kimi Code CLI facts (see https://www.kimi.com/code/docs/en/):
"
"   * A new session is `kimi`; resuming is `kimi --session <id>`. There is no
"     way to pre-assign an id or a name: the CLI mints a session id itself
"     and only writes it to disk once the session has content, so a freshly
"     spawned session is tracked provisionally and re-keyed when its real id
"     shows up (see autoload/kimi/session.vim, s:adopt_id()).
"
"   * Sessions live under $KIMI_CODE_HOME (default ~/.kimi-code):
"       sessions/<workDirKey>/<sessionId>/state.json   metadata
"       session_index.jsonl                            id -> dir -> workDir
"     The index is the supported lookup path, so the workDirKey encoding is
"     never reverse-engineered here.
"
"   * state.json carries the title (user-set or generated), the last prompt,
"     and millisecond timestamps — everything the panel needs to place and
"     label a session, with no need to read the agent event stream.
"
"   * Models are user configuration, not a fixed list, so :KimiModel hands
"     over to the CLI's own picker by sending a bare /model.

" Status patterns read from the bottom of a session's terminal. Kimi's TUI
" shows numbered options (1~9) while an approval waits, so a numbered list,
" a "Do you want" question or a (y/n) prompt counts as waiting. There is no
" documented working footer, so working state is detected from terminal
" output activity instead of a pattern.
let s:WORKING_PAT = ''
let s:WAITING_PAT = '\%(^\|\n\)\s*❯\=\s*1\.\s\|Do you want\|(y/n)'

function! kimi#cli#working_pat() abort
  return s:WORKING_PAT
endfunction

function! kimi#cli#waiting_pat() abort
  return s:WAITING_PAT
endfunction

" ── data root ────────────────────────────────────────────────────────────────

" Where the CLI keeps everything: $KIMI_CODE_HOME wins, else ~/.kimi-code.
function! kimi#cli#home() abort
  return empty($KIMI_CODE_HOME) ? expand('~/.kimi-code') : $KIMI_CODE_HOME
endfunction

" ── launching ────────────────────────────────────────────────────────────────

" The launch command: one built-in value. Tests swap it through
" kimi#cli#_set_cmd() so a stand-in is spawned instead of the real CLI.
let s:cmd = 'kimi'

" {spec} is {'id', 'resume'}. A List, never a string: :terminal and
" job_start() run no shell, so a string command is split on whitespace with
" no quote handling. The List form passes each argument through untouched.
function! kimi#cli#argv(spec) abort
  let l:argv = split(s:cmd)
  if get(a:spec, 'resume', 0) && !empty(get(a:spec, 'id', ''))
    call extend(l:argv, ['--session', a:spec.id])
  endif
  return l:argv
endfunction

" ── the session index ────────────────────────────────────────────────────────

" The parsed session index: a list of {'sessionId', 'sessionDir', 'workDir'}.
" Cached until the file's mtime changes; readers never pay for a re-parse on
" a hot path.
let s:index = []
let s:index_ftime = -1

function! s:read_index() abort
  let l:path = kimi#cli#home() . '/session_index.jsonl'
  let l:ftime = getftime(l:path)
  if l:ftime == s:index_ftime
    return s:index
  endif
  let s:index_ftime = l:ftime
  let s:index = []
  if !filereadable(l:path)
    return s:index
  endif
  for l:line in readfile(l:path)
    if empty(l:line)
      continue
    endif
    try
      let l:rec = json_decode(l:line)
    catch
      continue
    endtry
    if type(l:rec) == v:t_dict && !empty(get(l:rec, 'sessionId', ''))
          \ && !empty(get(l:rec, 'sessionDir', ''))
      call add(s:index, {
            \ 'sessionId': l:rec.sessionId,
            \ 'sessionDir': l:rec.sessionDir,
            \ 'workDir': get(l:rec, 'workDir', ''),
            \ })
    endif
  endfor
  return s:index
endfunction

" Every session id already on disk for {cwds}, as a dict for cheap lookup.
function! kimi#cli#ids(cwds) abort
  let l:seen = {}
  for l:rec in s:read_index()
    if index(a:cwds, l:rec.workDir) >= 0
      let l:seen[l:rec.sessionId] = 1
    endif
  endfor
  return l:seen
endfunction

" The directory holding {id}'s session data, or '' when the index names no
" such session (nothing on disk yet, or an id this Vim minted provisionally).
function! kimi#cli#session_dir(id) abort
  for l:rec in s:read_index()
    if l:rec.sessionId ==# a:id
      return l:rec.sessionDir
    endif
  endfor
  return ''
endfunction

" One session's metadata by id, or {} when the index names no such session.
" 'named' reports whether the session carries a label somebody chose — a
" custom title set with /title, or a generated one.
function! kimi#cli#info(id) abort
  let l:dir = kimi#cli#session_dir(a:id)
  if empty(l:dir) || !isdirectory(l:dir)
    return {}
  endif
  let l:state = s:read_state(l:dir)
  return {
        \ 'name':    l:state.title,
        \ 'snippet': l:state.lastPrompt,
        \ 'named':   !empty(l:state.title),
        \ 'updated': l:state.updated,
        \ }
endfunction

" ── session metadata ─────────────────────────────────────────────────────────

" Read <dir>/state.json, filling in the fields this plugin relies on. A
" missing or unreadable state.json means a session directory the CLI has not
" finished writing: every field falls back to empty, and the caller decides
" how much of that it accepts.
function! s:read_state(dir) abort
  let l:state = {
        \ 'title':     '',
        \ 'lastPrompt': '',
        \ 'created':   getftime(a:dir),
        \ 'updated':   getftime(a:dir),
        \ 'custom_title': 0,
        \ }
  let l:path = a:dir . '/state.json'
  if !filereadable(l:path)
    return l:state
  endif
  try
    let l:data = json_decode(join(readfile(l:path), "\n"))
  catch
    return l:state
  endtry
  if type(l:data) != v:t_dict
    return l:state
  endif
  let l:state.title = s:trim(get(l:data, 'title', ''))
  let l:state.lastPrompt = s:trim_snippet(get(l:data, 'lastPrompt', ''))
  if type(get(l:data, 'createdAt', 0)) == v:t_number
    let l:state.created = l:data.createdAt / 1000
  endif
  if type(get(l:data, 'updatedAt', 0)) == v:t_number
    let l:state.updated = l:data.updatedAt / 1000
  endif
  let l:state.custom_title = get(l:data, 'isCustomTitle', 0) ? 1 : 0
  return l:state
endfunction

function! s:trim(text) abort
  return substitute(a:text, '^\s\+\|\s\+$', '', 'g')
endfunction

" Snippet text is cut to 60 characters on one line, the way the panel's
" '(unnamed …)' rows and store labels read best.
function! s:trim_snippet(text) abort
  let l:s = substitute(a:text, '[\r\n]\+', ' ', 'g')
  return strcharpart(s:trim(l:s), 0, 60)
endfunction

" How many sessions a sweep reads from disk, across all directories, newest
" first. Scanning reads one small state.json per candidate — cheap, but the
" panel is still only ever going to draw the top of the list.
let s:SCAN_LIMIT = 10

" Every session of the directories in {cwds} — the one Vim is in, plus every
" workspace of this repository. The CLI files a session under the directory
" it ran in, so a workspace session's record is invisible from the main
" checkout otherwise. Newest first, capped across the project rather than
" per directory.
"
" A record is:
"   id       the CLI's session id
"   path     the session directory (what purge deletes)
"   cwd      the working directory the session ran in
"   name     the CLI-side title, when it has one ('' until the session earns
"            one — generated titles arrive with the first turns)
"   snippet  the last prompt text, a label fallback when there is no title
"   created  unix seconds
"   updated  unix seconds
function! kimi#cli#sessions(cwds) abort
  let l:seen = {}
  let l:out  = []
  for l:rec in s:read_index()
    if index(a:cwds, l:rec.workDir) < 0 || has_key(l:seen, l:rec.sessionId)
      continue
    endif
    let l:seen[l:rec.sessionId] = 1
    let l:state = s:read_state(l:rec.sessionDir)
    call add(l:out, {
          \ 'id':      l:rec.sessionId,
          \ 'path':    l:rec.sessionDir,
          \ 'cwd':     l:rec.workDir,
          \ 'name':    l:state.title,
          \ 'snippet': l:state.lastPrompt,
          \ 'created': l:state.created,
          \ 'updated': l:state.updated,
          \ })
  endfor
  if empty(l:out)
    return []
  endif
  call sort(l:out, {a, b -> a:updated == b:updated ? 0
        \ : a:updated > b:updated ? -1 : 1})
  return l:out[0 : s:SCAN_LIMIT - 1]
endfunction

" ── completion ───────────────────────────────────────────────────────────────

" The CLI's built-in slash commands, from the slash-command reference.
let s:SLASH_COMMANDS = [
      \ {'word': '/login',            'menu': 'Log in to an account or platform'},
      \ {'word': '/logout',           'menu': 'Clear credentials for the current account'},
      \ {'word': '/provider',         'menu': 'Manage providers'},
      \ {'word': '/model',            'menu': 'Switch model'},
      \ {'word': '/secondary-model',  'menu': 'Pick the default subagent model'},
      \ {'word': '/settings',         'menu': 'Open the settings panel'},
      \ {'word': '/experiments',      'menu': 'Open the experimental feature panel'},
      \ {'word': '/permission',       'menu': 'Select a permission mode'},
      \ {'word': '/editor',           'menu': 'Configure the external editor'},
      \ {'word': '/theme',            'menu': 'Switch the color theme'},
      \ {'word': '/new',              'menu': 'Start a fresh session'},
      \ {'word': '/sessions',         'menu': 'Browse and resume sessions'},
      \ {'word': '/tasks',            'menu': 'Browse the background task list'},
      \ {'word': '/fork',             'menu': 'Fork the current session'},
      \ {'word': '/title',            'menu': 'Set the session title'},
      \ {'word': '/compact',          'menu': 'Compact the conversation context'},
      \ {'word': '/undo',             'menu': 'Undo recent prompts'},
      \ {'word': '/reload',           'menu': 'Reload config and the session'},
      \ {'word': '/reload-tui',       'menu': 'Reload TUI preferences'},
      \ {'word': '/init',             'menu': 'Generate AGENTS.md'},
      \ {'word': '/export-md',        'menu': 'Export the session as Markdown'},
      \ {'word': '/export-debug-zip', 'menu': 'Export the session as a debug ZIP'},
      \ {'word': '/import-sessions',  'menu': 'Import sessions from other CLIs'},
      \ {'word': '/copy',             'menu': 'Copy the last assistant message'},
      \ {'word': '/add-dir',          'menu': 'Add an extra workspace directory'},
      \ {'word': '/web',              'menu': 'Open the session in the web UI'},
      \ {'word': '/desktop',          'menu': 'Open the desktop app page'},
      \ {'word': '/yolo',             'menu': 'Ask When Needed permission mode'},
      \ {'word': '/auto',             'menu': 'Never Ask permission mode'},
      \ {'word': '/plan',             'menu': 'Toggle Plan mode'},
      \ {'word': '/swarm',            'menu': 'Turn swarm mode on or off'},
      \ {'word': '/tower',            'menu': 'Show Tower status'},
      \ {'word': '/goal',             'menu': 'Start or manage an autonomous goal'},
      \ {'word': '/help',             'menu': 'Show keyboard shortcuts and commands'},
      \ {'word': '/btw',              'menu': 'Side conversation in a forked sub-Agent'},
      \ {'word': '/usage',            'menu': 'Show token usage and quota'},
      \ {'word': '/status',           'menu': 'Show session runtime state'},
      \ {'word': '/mcp',              'menu': 'List MCP servers and their status'},
      \ {'word': '/plugins',          'menu': 'Open the plugin manager'},
      \ {'word': '/version',          'menu': 'Display the CLI version'},
      \ {'word': '/feedback',         'menu': 'Submit feedback'},
      \ {'word': '/exit',             'menu': 'Exit the CLI'},
      \ ]

" The skill directories the CLI scans, project scope before user scope.
function! s:skill_dirs(cwd) abort
  let l:home = kimi#cli#home()
  return [a:cwd . '/.kimi-code/skills', a:cwd . '/.agents/skills',
        \ l:home . '/skills', expand('~/.agents/skills')]
endfunction

" Skills the CLI would register as slash commands: directory form
" (<name>/SKILL.md) and flat form (<name>.md), directory form winning.
function! s:skills(cwd) abort
  let l:out = []
  for l:dir in s:skill_dirs(a:cwd)
    if !isdirectory(l:dir)
      continue
    endif
    for l:sub in glob(l:dir . '/*/SKILL.md', 0, 1)
      call add(l:out, {'word': '/' . fnamemodify(fnamemodify(l:sub, ':h'), ':t'),
            \ 'menu': 'Skill'})
    endfor
    for l:md in glob(l:dir . '/*.md', 0, 1)
      call add(l:out, {'word': '/' . fnamemodify(l:md, ':t:r'),
            \ 'menu': 'Skill'})
    endfor
  endfor
  return l:out
endfunction

" Built-in slash commands plus the skills installed at user and project
" level. Kimi has no @agent concept, so the agent list is empty and @
" completes files alone.
function! kimi#cli#completion(cwd) abort
  return {'commands': copy(s:SLASH_COMMANDS) + s:skills(a:cwd), 'agents': []}
endfunction

" ── test seam ────────────────────────────────────────────────────────────────

" Forget the cached index (tests point $KIMI_CODE_HOME at a fixture).
function! kimi#cli#_reset() abort
  let s:index       = []
  let s:index_ftime = -1
  let s:cmd         = 'kimi'
endfunction

" Spawn a stand-in instead of the CLI. Test-only counterpart of the built-in
" launch command.
function! kimi#cli#_set_cmd(cmd) abort
  let s:cmd = a:cmd
endfunction
