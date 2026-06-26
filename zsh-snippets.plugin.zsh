# zsh-snippets plugin entry point (oh-my-zsh compatible).
# Sourced automatically by oh-my-zsh when listed in `plugins=(...)`.
# Also works with any plugin manager or plain `source` of this file.

# Load zsh-autosuggestions BEFORE zsh-snippets so its strategy and accept
# widgets are in place by the time this plugin's precmd hook fires.

source "${0:A:h}/zsh-snippets.zsh"
