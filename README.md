# kimi.vim

A Vim plugin that opens the [Kimi Code CLI](https://www.kimi.com/code/docs/en/) in a terminal split, giving you persistent AI sessions alongside your code.

Run as many sessions as you like, name them, and switch between them from a NERDTree-style side panel grouped by what they're doing or by workspace and branch.

The plugin has **no configuration** — every behaviour has one built-in value.

## Requirements

- Vim 8.1+ (with `+terminal`)
- The `kimi` CLI on your `$PATH`

## Installation

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug '<you>/kimi.vim'
```

Or copy `plugin/kimi.vim`, `autoload/kimi.vim`, and `autoload/kimi/` into your plugin directory manually.

## Usage

| Mapping | Command | Action |
|---------|---------|--------|
| `<leader>ko` | `:KimiOpen` | Focus a session, starting one if none is running |
| `<leader>kn` | `:KimiNew` | Start a session even when others are already running |
| `<leader>ks` | `:KimiSessions` | Toggle the session panel |
| `<leader>kw` | `:KimiWorkspaces` | Choose the workspace (git worktree) to work in |
| `<C-a>` | `:KimiSidebars` | Raise or dismiss the whole sidebar column |
| `<leader>kt` | `:KimiToggle` | Show/hide a kimi window |
| `<leader>kx` | `:KimiClose` | End a session |
| `<leader>kf` | `:KimiFocus` | Move cursor to a kimi window (enters insert mode) |
| `<leader>ke` | `:KimiExplain` | Explain the current file (normal) or selection (visual) |
| `<leader>ki` | `:KimiInput` | Toggle the input window for multi-line messages |
| `<leader>km` | `:KimiModel` | Switch model (hands over to the CLI's own picker) |
| `<leader>kh/l/k/j` | `:KimiWin*` | Navigate between windows |

`:KimiNew [name]` starts an extra session, and `:KimiRename [name]` renames one. When several sessions are running, commands that need just one show a picker; when only one is running, it is used without prompting.

Starting a session without naming it on the command line asks for a branch first, and gives the session its own checkout of that branch — see [Workspaces](#workspaces).

Inside the kimi terminal, press `<Esc><Esc>` to enter terminal-normal mode (so Vim handles the cursor and mouse). Single `<Esc>` is passed through to the CLI (interrupt, close popup).

## Input window

`<leader>ki` toggles a dedicated buffer for writing long, multi-line prompts. It opens as a 10-line split at the bottom. Pressing `<leader>ki` again discards the content and closes the window. To preserve your text, press `<C-c>` instead — it saves a draft and hides the window; reopening restores it.

The buffer is a `.md` file, so syntax highlighting works out of the box.

| Key | Action |
|-----|--------|
| `<C-s>` (insert or normal) | Send the message and close the window |
| `<C-c>` (normal) | Save draft and hide the window |
| `q` (normal) | Discard draft and close |

Type `/` to trigger slash-command completion — built-in commands plus skills found in the CLI's skill directories. Type `@` to complete file paths — file completions require [`rg`](https://github.com/BurntSushi/ripgrep) on your `$PATH` and support basename matching (e.g. `@kim` matches `doc/kimi.txt`).

A session is opened automatically if none is running.

## Session panel

`<leader>ks` toggles a panel listing every session — the ones running now and the ones you can resume. It has two views, swapped with `g`.

**By state**, which is what it opens on — which one is waiting for me?

```
Kimi Sessions           2 waiting

▾ Needs you (2)
  ✻ pick a diff base        wt · 2m
  ✻ rerun the tests?      root · 5m
▾ Working (1)
  ● panel rework          root · 1m
▾ Idle (1)
  ○ user_interface        root · 2h
▸ Done (10)
```

**By place** — group, then branch — for when the question really is what is happening in that checkout.

`✻` waiting for you, `●` working, `○` idle, `✗` closed but resumable.

Waiting is read from the bottom rows of the session's terminal, where the CLI shows its approval panel — a numbered list of options. Working has no documented terminal footer, so it is detected from terminal output activity; one quiet for more than 30 seconds reads as idle.

### The buried tail

A **finished** session is buried — left out of the panel list, the way NERDTree leaves out dotfiles — when it carries no label at all (never messaged, so no title), or when nobody has touched it for 2 days. Press `I` to show the buried ones and again to put them away; renaming one with `r` un-hides it until it goes stale. They are hidden from the panel list only: a buried session still counts in the header while it runs, still appears in the pickers and in `:KimiResume`, and still runs.

### Sharing a column with NERDTree

The panel and NERDTree would otherwise form two columns and swallow most of the screen. When both are open they share one column, panel on top, sized by percentage of the screen — the session panel takes 25%, the diff tree 40%, and the bottom-most sidebar (NERDTree, when it is installed) absorbs the rest. Resize any of them by hand and it stays put.

`<C-a>` (`:KimiSidebars`) raises all three at once and dismisses them again once they are all showing. It is mapped in normal mode only, so `<C-a>` still increments a number under the cursor from insert mode and visual mode.

The panel uses NERDTree's palette — group nodes coloured like directories, session names like files — so the sidebar reads as one thing. Override `KimiSessionProject`, `KimiSessionBranch`, `KimiSessionName`, `KimiSessionActive` and friends to restyle just the panel; a link you set is never overwritten.

| Key | Action |
|-----|--------|
| `<CR>` / `o` | Open the session, or fold a group |
| `i` | Open in a horizontal split |
| `s` | Open in a vertical split |
| `t` | Open in a new tab |
| `n` | Start a session where the cursor is, asking only its name |
| `N` | Start a session, asking for a branch and then a name |
| `g` | Swap the top level: state ⇄ place |
| `/` | Filter every group |
| `r` | Rename |
| `d` | End the session (transcript kept, so it stays resumable) |
| `D` | Purge the session and delete its session data |
| `R` | Rescan the on-disk sessions |
| `I` | Show or hide the buried sessions |
| `<Space>` / `za` | Fold or unfold |
| `q` | Hide the panel |
| `?` | Toggle the inline key reference |

Hiding the panel never stops a session. Status is polled only while the panel is visible.

## Sessions on disk

The CLI persists every session under `$KIMI_CODE_HOME` (default `~/.kimi-code`): one directory per session under `sessions/`, indexed by `session_index.jsonl`, with metadata (title, last prompt, timestamps) in `state.json`. The plugin never edits those files — it reads the index and `state.json` to list, label and resume sessions; purge (`D`) deletes the session directory.

The CLI mints its own session ids and only writes them to disk once a session has content. So a session started here starts life under a provisional id and is re-keyed onto the CLI's id when one appears; a session started but never messaged has nothing to resume, and resuming it starts a fresh session that keeps the panel row and its name.

Names typed in the panel are kept in `data/sessions.json` inside the plugin directory. A plugin update or reinstall (`:PlugUpdate`, deleting the bundle directory) deletes that file and every Vim-side name with it — the CLI-side title (set with `/title`, or generated) is the label that survives.

## Model switching

`:KimiModel` (or `<leader>km`) sends a bare `/model` to the session, opening the CLI's own model picker. Model aliases are user configuration (providers and models in the CLI's `config.toml`), so the plugin offers no list of its own. Opens a new session first if none is running.

## Workspaces

A workspace is a git worktree a session owns: its own checkout of one branch, so two sessions can work on two branches at once without fighting over one directory.

Starting a session asks two questions:

```
Branch (blank for no workspace): <Tab> completes local and remote branches
Session name:
```

| Branch | Name | Result |
|--------|------|--------|
| given | given | A workspace called `<name>`, checked out on `<branch>` |
| given | blank | A workspace named after the branch |
| blank | given | No workspace — the session runs in the selected workspace, or where you are |
| blank | blank | The same, and the session labels itself from its CLI title or first prompt |

The panel's `N` runs exactly these two prompts. Its `n` runs only the second: the new session lands where the cursor already is. Leave the name blank and the session labels itself.

The worktree is created beside the main checkout as `<repo>-<name>`.

A branch that matches nothing becomes a new branch off `HEAD`; one that exists only on a remote gets a local tracking branch. Names are unique per repository, so a second workspace called `feature-branch` becomes `feature-branch-1`, then `feature-branch-2`, and slashes become dashes (`feature/deep` → `feature-deep`).

A branch that already has a checkout is not an error — the session runs in that checkout. Nothing is created only when the directory is in the way; you are told, and the session runs where you already were. Removing a workspace is left to `git worktree remove`.

`<leader>kw` (`:KimiWorkspaces`) lists the main checkout and every workspace, and re-roots NERDTree onto the one you pick, so the file tree shows that checkout and nothing else. Sessions started without a branch run there. It also runs `:tcd` to that workspace's directory, so the current tab's working directory — and anything that depends on it, like `:Git status` — follows the switch too; other tabs are left alone.

## Git diff tree

`<leader>kd` opens a tree of every file that differs from the base branch — committed and uncommitted together — grouped by worktree:

```
Git Diff                      main

▾ kimi-plugin
  ▾ main
    ▾ autoload/kimi
      [✚|✹] difftree.vim
      [✚]   panel.vim
      [ |✭] cli.vim
    ▾ doc
      [✹]   kimi.txt
  ▾ hotfix/e947 (wt-hotfix)
    ▾ autoload/kimi
      [✹]   input.vim
  ▾ feature/session-panel (no worktree)
    ▾ autoload/kimi
      [✚]   session.vim
```

One row per **branch**, directly under the project. A worktree holds exactly one branch, so it is named in the label instead: `hotfix/e947 (wt-hotfix)`, or `(no worktree)` when nothing checks the branch out.

The branch you are actually sitting on comes first: it is what shows *your* uncommitted work. When a branch is the base, the committed half is compared against its upstream instead, so unpushed commits still show.

Branch names are **yellow**, except a branch with no remote-tracking branch — work that exists only on your machine — which is **grey**. In the status glyphs, added is **green** and removed is **red**, taken from your `DiffAdd` and `DiffDelete` colours.

Each branch can diff against a base of its own: press `b` on a branch row to set it, or clear it with an empty answer. The choice persists across Vim restarts, keyed by repository. `B` sets a session-wide default for branches with no base of their own. Otherwise the base is auto-detected: `origin/HEAD`, then `main`, then `master`.

The branches listed are the union of every worktree, every branch a session has run on (live or closed, taken from the session registry), and the branch you are on now. A branch no longer checked out anywhere is listed under the root workspace beside the branch that *is* checked out there, marked `(no worktree)` and dimmed; it shows **committed changes only**.

Each row carries a bracketed field with **two slots**: the first says what the branch did to the file relative to the base; the second what the working tree has done since:

| Field | Meaning |
|---|---|
| `[✚]` | added on this branch, clean in the working tree |
| `[✹]` | modified on this branch, clean in the working tree |
| `[ \|✹]` | untouched by the branch, modified in the working tree |
| `[✚\|✹]` | added on this branch **and** modified since |
| blank | neither |

The glyphs come from [nerdtree-git-plugin](https://github.com/Xuyuanp/nerdtree-git-plugin), so the diff tree and NERDTree describe git state in the same alphabet. If the plugin is installed, its `gitstatus#getIndicator()` is called directly, so `g:NERDTreeGitStatusUseNerdFonts` and any `g:NERDTreeGitStatusIndicatorMapCustom` you set carry over automatically; without it, an embedded copy of its defaults is used.

| Column | Git letter | Status | Glyph | ASCII |
|---|---|---|---|---|
| branch vs base | `A` | Staged | `✚` | `+` |
| branch vs base | `M` | Modified | `✹` | `*` |
| branch vs base | `D` | Deleted | `✖` | `D` |
| branch vs base | `R` `C` | Renamed | `➜` | `R` |
| working tree | `M` | Modified | `✹` | `*` |
| working tree | `A` | Staged | `✚` | `+` |
| working tree | `D` | Deleted | `✖` | `D` |
| working tree | `R` `C` | Renamed | `➜` | `R` |
| working tree | untracked | Untracked | `✭` | `!` |

> **Limitation:** the tree uses `git diff --name-status`, not `git status --porcelain`, so staged-but-uncommitted work cannot be told apart from unstaged, and `═ Unmerged` never appears. Ignored and clean files are not listed at all.

## Help

Full documentation is available inside Vim:

```
:help kimi
```

## License

MIT
