# zsh-snippets

Name-based snippets for zsh that plug into [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions)
and [LuaSnip](https://github.com/L3MON4D3/LuaSnip).

Type a snippet name, let zsh-autosuggestions ghost-complete it like history,
press **Right-Arrow** to expand it inline. If the snippet has `<placeholders>`,
Neovim opens with LuaSnip jump nodes so you can fill them in, then drops the
edited command back into the prompt for one last look before you press Enter.

```
$ kill9      <-- you type this much
$ kill9      <-- the grey ghost completes the name (snippet strategy)
$ kill -9 id <-- Right-Arrow: nvim opens, "id" is a jump node
$ kill -9 4242   <-- :wq in nvim: the filled command lands back in the prompt
```

## Requirements

- zsh 5.0.8+
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) (load it **before** this plugin)
- [`jq`](https://stedolan.github.io/jq/) (parses `snippets.json`)
- [Neovim](https://neovim.io/) + [LuaSnip](https://github.com/L3MON4D3/LuaSnip) for the `<param>` editing flow
  (without LuaSnip the editor still opens; you just edit raw text)

## Install

### One-shot (recommended)

If you use **oh-my-zsh**, run the installer — it drops the plugin in
`$ZSH_CUSTOM/plugins/`, creates `~/.local/share/zsh-snippets/snippets.json`
from the starter file, and patches `~/.zshrc` so `plugins=(...)` lists
`zsh-snippets` right after `zsh-autosuggestions`:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Hexdigest123/zsh-snippet/main/install.sh)"
```

Then restart your shell:

```zsh
exec zsh
```

The installer is idempotent and backs up `~/.zshrc` to `~/.zshrc.zsh-snippets.bak`
before editing. Run it from a local clone with `./install.sh`; it'll symlink the
clone into `$ZSH_CUSTOM` so edits stay live. Override the source repo or branch
with `GH_REPO=you/repo` / `GH_BRANCH=dev` if you fork.

### Manual

```zsh
git clone https://github.com/Hexdigest123/zsh-snippet \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-snippets
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snippets"
cp ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-snippets/snippets.example.json \
   "${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snippets/snippets.json"
```

In `~/.zshrc`, load `zsh-autosuggestions` **first**, then `zsh-snippets`:

```zsh
plugins=(
  git
  zsh-autosuggestions   # must come before zsh-snippets
  zsh-snippets
)
```

### Other plugin managers / plain `source`

The plugin waits on a `precmd` hook until zsh-autosuggestions is detected, so a
slightly wrong load order is self-healing. To use it without a plugin manager:

```zsh
source /path/to/zsh-snippets/zsh-snippets.plugin.zsh
```

## Snippet file format

```json
[
  { "name": "kill9",      "content": "kill -9 <id>" },
  { "name": "sshServer",  "content": "ssh root@<host> -p <port>" }
]
```

- `name`    — typed at the prompt (and ghost-completed by the `snippet` strategy).
- `content` — what it expands to.
- `<placeholder>` — any token matching `<...>` with no spaces/`<>` inside becomes
  a LuaSnip jump node when the snippet is expanded.

Override the file location with `ZSH_SNIPPETS_FILE`. Reload on the fly with:

```zsh
zsh-snippets-reload
```

## How it works

1. **Suggestion.** The plugin registers a `snippet` strategy into
   `ZSH_AUTOSUGGEST_STRATEGY`. When the last word on the line is a strict
   prefix of a snippet name, the strategy ghosts the rest of that name.
2. **Expansion.** Right-Arrow is rebound to a custom widget
   (`zsh-snippets-expand-or-accept`). It looks at the word that would be on
   the line after accepting the ghost; if that word is a snippet name it
   expands the snippet. Otherwise it calls `zle forward-char`, which is the
   exact behavior Right-Arrow had before (accept the ghost, or move cursor).
3. **Parameter editing.** If the content has `<placeholders>`, the plugin
   writes it to a temp file and opens Neovim with `lua/zsh-snippets.lua`,
   which rewrites `<x>` to LSP `${1:x}` syntax and calls `ls.lsp_expand()`.
   You fill the placeholders with LuaSnip's jump keys, then `:wq` ships the
   edited command back to the prompt — no auto-execute, you press Enter.

## Configuration

| Variable                 | Default                                            | Purpose                                              |
|--------------------------|----------------------------------------------------|------------------------------------------------------|
| `ZSH_SNIPPETS_FILE`      | `${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snippets/snippets.json` | Where to read snippets from          |
| `ZSH_SNIPPETS_EDITOR`    | `nvim`                                             | Editor command used for the `<param>` flow           |

To put `snippet` after `history` instead of before it (so history wins ties),
reassign after load:

```zsh
ZSH_AUTOSUGGEST_STRATEGY=(history completion snippet)
```

## Commands

| Command               | Action                                            |
|-----------------------|---------------------------------------------------|
| `zsh-snippets-reload` | Re-read `snippets.json` (after editing it).       |

## Notes

- Right-Arrow fallback is the original autosuggestion accept — so when the
  current word isn't a snippet, nothing changes.
- Snippet names must be unique; duplicates overwrite earlier entries.
- `<placeholder>` detection requires the angle-bracket body to contain no
  spaces and no nested `<>`. `grep <pattern>` is fine; `echo <hi there>` is not.

## Development

Three test scripts live under `test/`:

```zsh
zsh test/unit.zsh         # loader, helpers, autosuggestion strategy
zsh test/install.zsh      # install.sh .zshrc patching across all shapes (sandbox)
shellcheck install.sh     # installer lint
nvim --headless /tmp/s.sh "+set runtimepath+=$PWD" \
  "+lua require('zsh-snippets').edit()" "+qa!"   # smoke-test the LuaSnip helper
```
