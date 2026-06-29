# Nushell aliases

alias l  = eza --icons=always --group-directories-first
alias ls = eza --icons --grid
alias la = l -a
alias ll = l -a1
alias lt = eza --icons=always --group-directories-first --tree --level 1

alias mv    = mv -v
alias cp    = cp -v
alias mkdir = mkdir -v
alias tree  = eza --icons=always --group-directories-first --tree --level 1
alias ncdu  = ncdu --color dark --show-percent
alias clear = clear -k
alias c = clear
alias du = dust

alias nv = nvim
alias snv = steam-run nvim
alias man = tldr
alias cal = cal -t

def chafa [...args] {
  with-env { TERM: xterm-kitty } {
    ^chafa ...$args
  }
}
