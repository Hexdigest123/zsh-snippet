#!/usr/bin/env zsh
# Sandbox test for install.sh: fake HOME per scenario, verify .zshrc patching
# and idempotency without touching the real environment.

emulate -L zsh
setopt local_options err_return
PLUGIN_DIR="${0:A:h:h}"
INSTALL="$PLUGIN_DIR/install.sh"

setup_fake_home() {
	local home="$1"
	rm -rf "$home"
	mkdir -p "$home/.oh-my-zsh/custom/plugins"
	# Provide a zsh-autosuggestions marker so the dep check is quiet.
	mkdir -p "$home/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
	# ZSH_CUSTOM must point at the fake tree.
	export ZSH_CUSTOM="$home/.oh-my-zsh/custom"
	export ZSH="$home/.oh-my-zsh"
	unset XDG_DATA_HOME
	export HOME="$home"
}

pass=0; fail=0
check() {
	local desc="$1" got="$2" want="$3"
	if [[ "$got" == *"$want"* ]]; then
		pass=$((pass + 1))
		print -P "%F{green}ok%f   -- $desc"
	else
		fail=$((fail + 1))
		print -P "%F{red}FAIL%f -- $desc"
		print "       want: [$want]"
		print "       got : [$got]"
	fi
}

run_install() { sh "$INSTALL" >/tmp/inst.log 2>&1; }

# --- Scenario 1: single-line plugins WITH zsh-autosuggestions ----------------
H="/tmp/zt-home-1"; setup_fake_home "$H"
print 'plugins=(git zsh-autosuggestions)' > "$H/.zshrc"
run_install
rc=$(<"$H/.zshrc")
check "1: single-line inserts after autosuggestions" "$rc" 'plugins=(git zsh-autosuggestions zsh-snippets)'
check "1: plugin symlinked into custom"     "$(readlink "$H/.oh-my-zsh/custom/plugins/zsh-snippets")" "$PLUGIN_DIR"
check "1: snippets.json copied"             "$(cat "$H/.local/share/zsh-snippets/snippets.json" | head -c 20)" '['
check "1: backup created"                   "$(<"$H/.zshrc.zsh-snippets.bak")" 'plugins=(git zsh-autosuggestions)'

# --- Scenario 2: multi-line plugins with autosuggestions --------------------
H="/tmp/zt-home-2"; setup_fake_home "$H"
printf 'plugins=(\n  git\n  zsh-autosuggestions\n)\n' > "$H/.zshrc"
run_install
rc=$(<"$H/.zshrc")
check "2: multi-line inserts after autosuggestions" "$rc" $'  zsh-autosuggestions zsh-snippets'

# --- Scenario 3: single-line plugins WITHOUT autosuggestions ----------------
H="/tmp/zt-home-3"; setup_fake_home "$H"
print 'plugins=(git)' > "$H/.zshrc"
run_install
rc=$(<"$H/.zshrc")
check "3: inserts before closing paren" "$rc" 'plugins=(git zsh-snippets)'

# --- Scenario 4: multi-line plugins WITHOUT autosuggestions -----------------
H="/tmp/zt-home-4"; setup_fake_home "$H"
printf 'plugins=(\n  git\n)\n' > "$H/.zshrc"
run_install
rc=$(<"$H/.zshrc")
check "4: multi-line inserts before paren" "$rc" $'  zsh-snippets\n)'

# --- Scenario 5: already patched -> no-op -----------------------------------
H="/tmp/zt-home-5"; setup_fake_home "$H"
print 'plugins=(git zsh-autosuggestions zsh-snippets)' > "$H/.zshrc"
expected_before="$H/.zshrc.zsh-snippets.bak"
rm -f "$expected_before"  # ensure no backup gets created
run_install
rc=$(<"$H/.zshrc")
check "5: already patched -> unchanged" "$rc" 'plugins=(git zsh-autosuggestions zsh-snippets)'
check "5: no backup created on no-op"    "$([[ -f "$expected_before" ]] && echo backup-exists || echo no-backup)" "no-backup"

# --- Scenario 6: no plugins line at all -> append ---------------------------
H="/tmp/zt-home-6"; setup_fake_home "$H"
print '# my zshrc\nalias x=y' > "$H/.zshrc"
run_install
rc=$(<"$H/.zshrc")
check "6: appends plugins block when absent" "$rc" 'plugins=(zsh-autosuggestions zsh-snippets)'

# --- Scenario 7: snippets.json not overwritten ------------------------------
H="/tmp/zt-home-7"; setup_fake_home "$H"
mkdir -p "$H/.local/share/zsh-snippets"
print '[{"name":"mine","content":"echo mine"}]' > "$H/.local/share/zsh-snippets/snippets.json"
print 'plugins=(git zsh-autosuggestions)' > "$H/.zshrc"
run_install
rc=$(<"$H/.local/share/zsh-snippets/snippets.json")
check "7: preserves existing snippets.json" "$rc" 'echo mine'

# --- Scenario 8: re-run is fully idempotent ---------------------------------
H="/tmp/zt-home-8"; setup_fake_home "$H"
print 'plugins=(git zsh-autosuggestions)' > "$H/.zshrc"
run_install
first=$(<"$H/.zshrc")
run_install
second=$(<"$H/.zshrc")
check "8: idempotent on second run" "$second" 'plugins=(git zsh-autosuggestions zsh-snippets)'
[[ "$first" == "$second" ]] && check "8: second run produces identical file" "yes" "yes" || check "8: second run produces identical file" "no" "yes"

# --- Scenario 9: curl-pipe style (no local files) -> git clone --------------
# Network-dependent: the repo must be public+pushed for the clone to succeed.
# We only hard-assert the .zshrc patch; the clone result is informational.
H="/tmp/zt-home-9"; setup_fake_home "$H"
print 'plugins=(git zsh-autosuggestions)' > "$H/.zshrc"
cp "$INSTALL" /tmp/zt-install-alone.sh
HOME="$H" ZSH_CUSTOM="$H/.oh-my-zsh/custom" sh /tmp/zt-install-alone.sh >/tmp/inst9.log 2>&1 || true
rc=$(<"$H/.zshrc")
check "9: .zshrc patched even if clone fails" "$rc" 'plugins=(git zsh-autosuggestions zsh-snippets)'
if [[ -f "$H/.oh-my-zsh/custom/plugins/zsh-snippets/zsh-snippets.plugin.zsh" ]]; then
	check "9: plugin cloned from GitHub" "yes" "yes"
else
	print -P "%F{yellow}skip%f -- 9: clone skipped (repo not public/pushed yet; will work post-publish)"
fi

print -- "\n$pass passed, $fail failed"
(( fail == 0 ))
