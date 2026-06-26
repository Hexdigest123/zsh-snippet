# zsh-snippets: name-based snippet expansion that hooks into zsh-autosuggestions.
#
# Workflow:
#   1. Type a snippet name (or a prefix of it). zsh-autosuggestions will ghost
#      the rest of the name using the `snippet` strategy provided here.
#   2. Press Right-Arrow.
#        - If the current word (after accepting the ghost, if any) is a snippet
#          name, it is expanded inline to the snippet's content.
#        - Otherwise Right-Arrow behaves exactly as normal (accept the
#          autosuggestion, or move the cursor).
#   3. If the snippet content contains `<param>` placeholders, Neovim is
#      opened with LuaSnip's jump-node UI so you can fill each parameter.
#      On `:wq` the edited command is dropped back into the prompt for a
#      final look/Enter to run.
#
# Snippet source: ${ZSH_SNIPPETS_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snippets/snippets.json}
# Schema: [ { "name": "someName", "content": "kill -9 <id>" }, ... ]

# Guard against double-loading.
(( ${+ZSH_SNIPPETS_LOADED} )) && return
typeset -g ZSH_SNIPPETS_LOADED=1

# Directory this file lives in (used to locate lua/zsh-snippets.lua for nvim).
typeset -g ZSH_SNIPPETS_PLUGIN_DIR="${${(%):-%x}:A:h}"

# Override the snippet source file by setting ZSH_SNIPPETS_FILE before loading.
: ${ZSH_SNIPPETS_FILE:="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snippets/snippets.json"}
typeset -g ZSH_SNIPPETS_FILE

# Editor used for the parameter-editing step. Defaults to nvim (required for
# the LuaSnip jump flow); set ZSH_SNIPPETS_EDITOR to override.
: ${ZSH_SNIPPETS_EDITOR:=nvim}

#--------------------------------------------------------------------#
# Snippet store                                                      #
#--------------------------------------------------------------------#

# _ZSH_SNIPPETS       : associative array name -> content
# _ZSH_SNIPPETS_NAMES : ordered array of names (used by the strategy)

# (Re)load snippets from the JSON file. Safe to call at any time.
zsh-snippets-reload() {
	emulate -L zsh
	setopt local_options extended_glob warn_create_global

	typeset -gA _ZSH_SNIPPETS
	typeset -ga _ZSH_SNIPPETS_NAMES
	_ZSH_SNIPPETS=()
	_ZSH_SNIPPETS_NAMES=()

	local file="$ZSH_SNIPPETS_FILE"
	if [[ ! -f "$file" ]]; then
		print -u2 "zsh-snippets: no snippet file at $file"
		print -u2 "zsh-snippets: create one, e.g.:"
		print -u2 "  mkdir -p \"${file:h}\" && cp \"${ZSH_SNIPPETS_PLUGIN_DIR}/snippets.example.json\" \"$file\""
		return 1
	fi

	if ! command -v jq >/dev/null 2>&1; then
		print -u2 "zsh-snippets: 'jq' is required to parse $file but was not found in PATH"
		return 1
	fi

	# Validate and project [name, content] with jq. Using @tsv gives us a
	# robust tab-separated stream; names/contents with tabs are escaped by jq.
	local name content
	while IFS=$'\t' read -r name content; do
		[[ -z "$name" ]] && continue
		_ZSH_SNIPPETS[$name]="$content"
		_ZSH_SNIPPETS_NAMES+=("$name")
	done < <(jq -jr '.[] | (.name // empty), "\t", (.content // empty), "\n"' "$file")

	return 0
}

#--------------------------------------------------------------------#
# Helpers                                                            #
#--------------------------------------------------------------------#

# Print the last shell word of $1. Uses zsh word splitting so quoted tokens
# are handled like the real command line.
_zsh_snippets_last_word() {
	emulate -L zsh
	local -a words
	words=("${(@z)1}")
	print -rn -- "${words[-1]}"
}

# True if $1 contains at least one <placeholder> token.
_zsh_snippets_has_params() {
	[[ "$1" == *"<"[^$'<>'$' \t']*">"* ]]
}

#--------------------------------------------------------------------#
# Autosuggestions strategy                                           #
#--------------------------------------------------------------------#

# Registered into ZSH_AUTOSUGGEST_STRATEGY as `snippet`.
# Receives the whole buffer as $1 and must set the global `suggestion` to a
# string that starts with the buffer.
_zsh_autosuggest_strategy_snippet() {
	emulate -L zsh

	typeset -g suggestion=
	local buffer="$1"
	(( ${#buffer} )) || return 0

	# Don't suggest if the user just finished a word (trailing whitespace).
	[[ "$buffer" == *[[:space:]] ]] && return 0

	local last_word
	last_word=$(_zsh_snippets_last_word "$buffer")
	(( ${#last_word} )) || return 0

	local name
	for name in "${(@)_ZSH_SNIPPETS_NAMES}"; do
		# Suggest only if there is something to add (strict prefix match).
		if [[ "$name" == "$last_word"* && "$name" != "$last_word" ]]; then
			local prefix_before="${buffer[1, $((${#buffer} - ${#last_word}))]}"
			suggestion="${prefix_before}${name}"
			return 0
		fi
	done
	return 0
}

#--------------------------------------------------------------------#
# Neovim / LuaSnip editing flow                                      #
#--------------------------------------------------------------------#

# Open $1 (snippet content) in nvim with LuaSnip jump nodes for each
# <placeholder>. On a clean `:wq`, prints the edited content to stdout
# (no trailing newline). Returns non-zero if the editor bails out or the
# user discards.
_zsh_snippets_edit_in_nvim() {
	emulate -L zsh

	local content="$1"
	local tmpfile
	# GNU mktemp honours the trailing .sh in the template, so we get a single
	# correctly-named temp file (no orphan to clean up).
	tmpfile=$(mktemp -p "${TMPDIR:-/tmp}" zsh-snippets.XXXXXX.sh 2>/dev/null) || return 2

	# Plain write of the content; the lua helper reads & transforms it.
	if ! print -rn -- "$content" > "$tmpfile"; then
		rm -f "$tmpfile"
		return 2
	fi

	# Editor attaches to the controlling tty so it can render normally.
	command "$ZSH_SNIPPETS_EDITOR" "$tmpfile" \
		"+set runtimepath+=$ZSH_SNIPPETS_PLUGIN_DIR" \
		"+lua require('zsh-snippets').edit()" \
		</dev/tty >/dev/tty 2>&1
	local rc=$?

	if (( rc != 0 )); then
		rm -f "$tmpfile"
		return $rc
	fi

	# Echo back the file content; $(...) already strips trailing newlines.
	local edited
	edited=$(<"$tmpfile")
	rm -f "$tmpfile"
	print -rn -- "$edited"
	return 0
}

#--------------------------------------------------------------------#
# Right-Arrow widget: expand-or-accept                               #
#--------------------------------------------------------------------#

_zsh_snippets_expand_or_accept_widget() {
	emulate -L zsh

	# Determine the buffer that would exist if the user accepted the current
	# suggestion (only meaningful when the cursor sits at the end of the line).
	local potential_buffer="$BUFFER"
	if (( CURSOR == ${#BUFFER} )) && (( ${#POSTDISPLAY} )); then
		potential_buffer="${BUFFER}${POSTDISPLAY}"
	fi

	(( ${#potential_buffer} )) || { zle forward-char; return; }

	# Don't try to expand if the line ends with whitespace.
	[[ "$potential_buffer" == *[[:space:]] ]] && { zle forward-char; return; }

	local last_word
	last_word=$(_zsh_snippets_last_word "$potential_buffer")
	(( ${#last_word} )) || { zle forward-char; return; }

	# Look up the snippet by name (use ${+...} so empty content still counts).
	(( ${+_ZSH_SNIPPETS[$last_word]} )) || { zle forward-char; return; }
	local content="${_ZSH_SNIPPETS[$last_word]}"

	# Chop the snippet name off the end, keep the preceding text.
	local prefix_before="${potential_buffer[1, $((${#potential_buffer} - ${#last_word}))]}"

	# Drop any active suggestion so it doesn't linger in POSTDISPLAY.
	POSTDISPLAY=

	# Content without placeholders: insert inline, no editor.
	if ! _zsh_snippets_has_params "$content"; then
		BUFFER="${prefix_before}${content}"
		CURSOR=${#BUFFER}
		zle -R
		return 0
	fi

	# Content with <param>: hand off to nvim + LuaSnip.
	local edited
	if edited=$(_zsh_snippets_edit_in_nvim "$content"); then
		BUFFER="${prefix_before}${edited}"
	else
		# Editor failed or aborted: fall back to raw content so the user
		# can still edit inline in the prompt.
		print -u2 $'\nzsh-snippets: editor exited without saving, inserted raw snippet'
		BUFFER="${prefix_before}${content}"
	fi
	CURSOR=${#BUFFER}
	zle -R
	return 0
}

#--------------------------------------------------------------------#
# One-shot initialization on first prompt                            #
#--------------------------------------------------------------------#

_zsh_snippets_init() {
	emulate -L zsh

	# Run only once.
	(( ${+ZSH_SNIPPETS_INITIALIZED} )) && return 0

	# Wait for zsh-autosuggestions to be available. If it never shows up,
	# keep the hook so we attach the moment it's loaded.
	(( ${+functions[_zsh_autosuggest_start]} )) || return 0

	typeset -g ZSH_SNIPPETS_INITIALIZED=1
	add-zsh-hook -d precmd _zsh_snippets_init

	zsh-snippets-reload

	# Keep zsh-autosuggestions from wrapping our widget with its `modify`
	# action. Without this, `_zsh_autosuggest_bind_widgets` (which runs on
	# every precmd) rebinds `zsh-snippets-expand-or-accept` to a wrapper that
	# clears POSTDISPLAY *before* our widget runs -- so we'd never see the
	# ghost text and could not accept-and-expand. Adding the glob to the
	# ignore list makes the next bind_widgets pass skip us for good.
	if (( ! ${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[(Ie)zsh-snippets-\*]} )); then
		ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(zsh-snippets-\*)
	fi

	# Register the widget (must happen with zle active, i.e. interactively).
	# `zle -N` also forces a clean rebind in case a previous autosuggestions
	# pass already wrapped the name.
	zle -N zsh-snippets-expand-or-accept _zsh_snippets_expand_or_accept_widget

	# Prepend our strategy so snippet names win over history when both match.
	if [[ -z "${ZSH_AUTOSUGGEST_STRATEGY[(r)snippet]}" ]]; then
		ZSH_AUTOSUGGEST_STRATEGY=(snippet "${ZSH_AUTOSUGGEST_STRATEGY[@]}")
	fi

	# Bind Right-Arrow (terminal-dependent sequences + terminfo + emacs/vi).
	local seq
	for seq in '^[[C' '^[OC' "$terminfo[kcuf1]"; do
		[[ -n "$seq" ]] || continue
		bindkey "$seq" zsh-snippets-expand-or-accept
	done
	# Make sure both keymaps get the binding.
	bindkey -M vicmd '^[[C' zsh-snippets-expand-or-accept 2>/dev/null
	bindkey -M vicmd '^[OC' zsh-snippets-expand-or-accept 2>/dev/null
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_snippets_init
