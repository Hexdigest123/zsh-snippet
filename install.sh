#!/usr/bin/env sh
# zsh-snippets installer. Designed to be safe to curl-pipe:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/Hexdigest123/zsh-snippet/main/install.sh)"
# or to run directly from a cloned copy:
#   ./install.sh
set -eu

PLUGIN_NAME="zsh-snippets"
DEFAULT_GH_REPO="Hexdigest123/zsh-snippet"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snippets"
SNIPPETS_FILE="$DATA_DIR/snippets.json"

BOLD="\033[1m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

info() { printf "${BLUE}==>${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}ok:${RESET}   %s\n" "$*"; }
warn() { printf "${YELLOW}warn:${RESET} %s\n" "$*"; }
err()  { printf "${RED}err:${RESET}  %s\n" "$*" >&2; }

need_confirm=0

#----------------------------------------------------------------------------
# Locate oh-my-zsh custom plugins directory.
#----------------------------------------------------------------------------
find_zsh_custom() {
    if [ -n "${ZSH_CUSTOM:-}" ] && [ -d "$ZSH_CUSTOM/plugins" ]; then
        echo "$ZSH_CUSTOM/plugins"
        return
    fi
    if [ -n "${ZSH:-}" ] && [ -d "$ZSH/custom/plugins" ]; then
        echo "$ZSH/custom/plugins"
        return
    fi
    if [ -d "$HOME/.oh-my-zsh/custom/plugins" ]; then
        echo "$HOME/.oh-my-zsh/custom/plugins"
        return
    fi
    echo ""
}

#----------------------------------------------------------------------------
# Place the plugin files at $1/zsh-snippets/.
#   - If already there: do nothing.
#   - If run from a clone containing the plugin: symlink it in (dev-friendly).
#   - Otherwise: git clone from GitHub.
#----------------------------------------------------------------------------
install_plugin_files() {
    plugins_dir="$1"
    target="$plugins_dir/$PLUGIN_NAME"

    if [ -f "$target/zsh-snippets.plugin.zsh" ]; then
        ok "plugin already installed at $target"
        return 0
    fi

    script_dir=""
    if [ -n "${0:-}" ]; then
        script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || script_dir=""
    fi

    if [ -n "$script_dir" ] && [ -f "$script_dir/zsh-snippets.plugin.zsh" ] && [ "$script_dir" != "$target" ]; then
        mkdir -p "$plugins_dir"
        ln -sfn "$script_dir" "$target"
        ok "symlinked $target -> $script_dir"
        return 0
    fi

    repo="${GH_REPO:-$DEFAULT_GH_REPO}"
    if ! command -v git >/dev/null 2>&1; then
        err "git is required to install when not running from a local clone"
        return 1
    fi
    mkdir -p "$plugins_dir"
    clone_args="--depth 1"
    if [ -n "${GH_BRANCH:-}" ]; then
        clone_args="$clone_args --branch $GH_BRANCH"
    fi
    # shellcheck disable=SC2086
    if git clone $clone_args "https://github.com/$repo.git" "$target"; then
        ok "cloned $repo into $target"
    else
        err "git clone failed. Set GH_REPO in the environment or clone manually."
        return 1
    fi
}

#----------------------------------------------------------------------------
# Install the starter snippets.json (never overwrite an existing one).
#----------------------------------------------------------------------------
install_snippets_file() {
    example=""
    plugins_dir="$(find_zsh_custom)"
    if [ -n "$plugins_dir" ] && [ -f "$plugins_dir/$PLUGIN_NAME/snippets.example.json" ]; then
        example="$plugins_dir/$PLUGIN_NAME/snippets.example.json"
    elif [ -n "${0:-}" ]; then
        script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || script_dir=""
        if [ -f "$script_dir/snippets.example.json" ]; then
            example="$script_dir/snippets.example.json"
        fi
    fi

    mkdir -p "$DATA_DIR"
    if [ -f "$SNIPPETS_FILE" ]; then
        ok "snippets.json already present at $SNIPPETS_FILE (left untouched)"
        return 0
    fi
    if [ -z "$example" ]; then
        warn "snippets.example.json not found; create $SNIPPETS_FILE yourself."
        return 0
    fi
    cp "$example" "$SNIPPETS_FILE"
    ok "wrote starter snippets to $SNIPPETS_FILE"
}

#----------------------------------------------------------------------------
# Patch ~/.zshrc so plugins=(...) contains zsh-snippets (idempotent, backed up).
# Inserts after zsh-autosuggestions if present, else before the closing paren.
#----------------------------------------------------------------------------
patch_zshrc() {
    zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        cat > "$zshrc" <<'EOF'

plugins=(zsh-autosuggestions zsh-snippets)
source "$ZSH/oh-my-zsh.sh"
EOF
        warn "no ~/.zshrc found; created a minimal one. Configure oh-my-zsh before restarting."
        return 0
    fi

    # Already patched?
    if grep -Eq '(^|[[:space:]])zsh-snippets([[:space:]]|\))' "$zshrc"; then
        ok "zsh-snippets already referenced in $zshrc"
        return 0
    fi

    cp "$zshrc" "$zshrc.zsh-snippets.bak"
    tmp="$zshrc.tmp"

    awk '
        BEGIN { in_plugins = 0; done = 0 }
        in_plugins == 0 && /^[[:space:]]*plugins=\(/ {
            in_plugins = 1
            if ($0 ~ /\)/) {
                if ($0 ~ /zsh-autosuggestions/) {
                    sub(/zsh-autosuggestions/, "zsh-autosuggestions zsh-snippets")
                } else {
                    sub(/\)/, " zsh-snippets)")
                }
                done = 1
                in_plugins = 0
            }
            print
            next
        }
        in_plugins == 1 && done == 0 {
            if ($0 ~ /zsh-autosuggestions/) {
                sub(/zsh-autosuggestions/, "zsh-autosuggestions zsh-snippets")
                done = 1
                in_plugins = 0
            } else if ($0 ~ /\)/) {
                printf "  zsh-snippets\n"
                done = 1
                in_plugins = 0
            }
            print
            next
        }
        { print }
    ' "$zshrc.zsh-snippets.bak" > "$tmp"

    if grep -q 'zsh-snippets' "$tmp"; then
        mv "$tmp" "$zshrc"
        ok "added zsh-snippets to plugins=(...) in $zshrc (backup: $zshrc.zsh-snippets.bak)"
    else
        rm -f "$tmp"
        {
            printf '\n# Added by zsh-snippets installer\n'
            printf 'plugins=(zsh-autosuggestions zsh-snippets)\n'
        } >> "$zshrc"
        warn "could not find a plugins=(...) block in $zshrc; appended one. Merge it with your existing plugins= line."
        need_confirm=1
    fi
}

#----------------------------------------------------------------------------
# Soft dependency checks (warn only).
#----------------------------------------------------------------------------
check_dependencies() {
    if ! command -v zsh >/dev/null 2>&1; then
        warn "zsh not found in PATH — this is a zsh plugin."
    fi
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found — required to parse snippets.json."
    fi
    if ! command -v nvim >/dev/null 2>&1; then
        warn "nvim not found — the <param> editor flow needs it (set ZSH_SNIPPETS_EDITOR to override)."
    fi

    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q 'zsh-autosuggestions' "$HOME/.zshrc"; then
            warn "zsh-autosuggestions is not referenced in ~/.zshrc. Install and enable it first:"
            printf '         git clone https://github.com/zsh-users/zsh-autosuggestions \\\n'
            printf '           %s/plugins/zsh-autosuggestions\n' "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
            need_confirm=1
        fi
    fi
}

#----------------------------------------------------------------------------
main() {
    printf '%b\n\n' "${BOLD}zsh-snippets installer${RESET}"

    plugins_dir="$(find_zsh_custom)"
    if [ -z "$plugins_dir" ]; then
        err "could not find an oh-my-zsh custom/plugins directory."
        err "set \$ZSH_CUSTOM or install oh-my-zsh first; for other setups, source"
        err "zsh-snippets.plugin.zsh manually from your ~/.zshrc."
        exit 1
    fi

    info "Installing plugin files into $plugins_dir"
    install_plugin_files "$plugins_dir"

    info "Setting up snippet data"
    install_snippets_file

    info "Patching ~/.zshrc"
    patch_zshrc

    info "Checking dependencies"
    check_dependencies

    printf "\n"
    if [ "$need_confirm" = "1" ]; then
        warn "one or more manual steps above need your attention."
    else
        ok "all done."
    fi
    printf '\nRestart your shell to load the plugin:\n    %b\n' "${BOLD}exec zsh${RESET}"
    printf '\nThen type a snippet name (e.g. %b) and press Right-Arrow.\n' "${BOLD}kill9${RESET}"
}

main "$@"
