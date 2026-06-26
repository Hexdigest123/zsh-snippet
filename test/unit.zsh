#!/usr/bin/env zsh
# Unit-style tests for zsh-snippets that don't need a real TTY.
# Stubs out `zle` so the plugin file sources cleanly in a non-interactive shell.

emulate -L zsh
setopt local_options err_return
zmodload zsh/zutil 2>/dev/null

# --- Stub out zle so the plugin file can be sourced non-interactively --------
zle() { :; }   # no-op: widget registration / bindkey calls won't blow up
bindkey() { :; }
autoload() { :; }
add-zsh-hook() { :; }

# --- Load the plugin --------------------------------------------------------
: ${ZSH_SNIPPETS_FILE:=/tmp/zsh-snippets-test.json}
source "${0:A:h:h}/zsh-snippets.zsh"

# --- Build a fixture --------------------------------------------------------
cat > "$ZSH_SNIPPETS_FILE" <<'JSON'
[
  { "name": "kill9",     "content": "kill -9 <id>" },
  { "name": "sshServer", "content": "ssh root@<host> -p <port>" },
  { "name": "todo",      "content": "echo TODO: hi" },
  { "name": "empty",     "content": "" }
]
JSON

zsh-snippets-reload

pass=0; fail=0
check() {
	local desc="$1" got="$2" want="$3"
	if [[ "$got" == "$want" ]]; then
		pass=$((pass + 1))
		print -P "%F{green}ok%f  -- $desc"
	else
		fail=$((fail + 1))
		print -P "%F{red}FAIL%f -- $desc"
		print "       got : [$got]"
		print "       want: [$want]"
	fi
}

# --- _ZSH_SNIPPETS keyed lookup ---------------------------------------------
check "loaded kill9 content"  "${_ZSH_SNIPPETS[kill9]}"     "kill -9 <id>"
check "loaded todo content"   "${_ZSH_SNIPPETS[todo]}"      "echo TODO: hi"
check "loaded empty content"  "${_ZSH_SNIPPETS[empty]}"     ""
(( ${+_ZSH_SNIPPETS[empty]} ))   && { check "empty key exists"    "yes" "yes"; }
(( ${+_ZSH_SNIPPETS[missing]} )) || { check "missing key absent"  "no"  "no";  }
check "names array length"    "${#_ZSH_SNIPPETS_NAMES}"    "4"

# --- _zsh_snippets_last_word ------------------------------------------------
_quoted='echo "a b"'
check "last word simple"      "$(_zsh_snippets_last_word 'kill -9 12')"   "12"
check "last word at start"    "$(_zsh_snippets_last_word 'kill9')"        "kill9"
check "last word quoted"      "$(_zsh_snippets_last_word "$_quoted")"     '"a b"'

# --- _zsh_snippets_has_params ----------------------------------------------
check "has param <id>"        "$(_zsh_snippets_has_params 'kill -9 <id>'   && echo y || echo n)"  "y"
check "no param"              "$(_zsh_snippets_has_params 'echo hi'        && echo y || echo n)"  "n"
check "param with hyphen"     "$(_zsh_snippets_has_params 'git <my-flag>'  && echo y || echo n)"  "y"

# --- _zsh_autosuggest_strategy_snippet -------------------------------------
unset suggestion
_zsh_autosuggest_strategy_snippet "kil"
check "strategy kil -> kill9"  "$suggestion" "kill9"

unset suggestion
_zsh_autosuggest_strategy_snippet "ssh"
check "strategy ssh prefix"    "$suggestion" "sshServer"

unset suggestion
_zsh_autosuggest_strategy_snippet "sshServ"
check "strategy full-ish name" "$suggestion" "sshServer"

unset suggestion
_zsh_autosuggest_strategy_snippet "sshServer"
check "exact name -> no ghost" "${suggestion:-<empty>}" "<empty>"

unset suggestion
_zsh_autosuggest_strategy_snippet "kill -9 ss"
check "strategy after prefix words" "$suggestion" "kill -9 sshServer"

unset suggestion
_zsh_autosuggest_strategy_snippet "kill -9 "
check "trailing space -> no suggestion" "${suggestion:-<empty>}" "<empty>"

unset suggestion
_zsh_autosuggest_strategy_snippet "totallyUnknown"
check "unknown prefix -> empty" "${suggestion:-<empty>}" "<empty>"

print -- "\n$pass passed, $fail failed"
(( fail == 0 ))
