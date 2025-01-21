#!/bin/bash

# ohhh sheeet nigga
alias sudo='sudo '

alias v="vimr -n $1"

alias ls='ls -alhG'
alias grep='rg --color=always'

alias cpwd='pwd | pbcopy'

# Git aliases
alias gs='git status'
alias gc='git checkout'
alias ga='git add'
alias gd='git diff'
alias gds='git diff --summary'

# ROT13-encode text. Works for decoding, too! ;)
alias rot13='tr a-zA-Z n-za-mN-ZA-M'

#chmod train
alias mx='chmod a+x'
alias 000='chmod 000'
alias 400='chmod 400'
alias 644='chmod 644'
alias 755='chmod 755'

# programs
#alias s='open -a "~/Applications/Sublime\ Text.app"'
alias chrome='open -a "Google Chrome"'
alias makepass='openssl rand -base64 32'
alias vbox="VBoxManage"

# YAML
alias yaml2json="ruby -ryaml -rjson -e 'puts JSON.pretty_generate(YAML.load(ARGF))'"

# Random
alias please="sudo !!"
alias hosts='sudo $EDITOR /etc/hosts'
alias sshconfig='$EDITOR ~/.ssh/config'
alias currentwifi="networksetup -getairportnetwork en0"
alias stfu="osascript -e 'set volume output muted true'"
alias pumpitup="osascript -e 'set volume 10'"

alias week='date +%V'

# List only directories
alias lsd='ls -l | grep "^d"'

# IP addresses
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"
alias localip="ipconfig getifaddr en0"
alias ips="ifconfig -a | perl -nle'/(\d+\.\d+\.\d+\.\d+)/ && print $1'"

# Enhanced WHOIS lookups
alias whois="whois -h whois-servers.net"

# Flush Directory Service cache
alias flush="dscacheutil -flushcache"

# Canonical hex dump; some systems have this symlinked
alias hd="hexdump -C"

# Trim new lines and copy to clipboard
alias trimcopy="tr -d '\n' | pbcopy"

# Recursively delete `.DS_Store` files
alias cleanup="find . -name '*.DS_Store' -type f -ls -delete"

# File size
alias fs="stat -f \"%z bytes\""

# Hide/show all desktop icons (useful when presenting)
alias hidedesktop="defaults write com.apple.finder CreateDesktop -bool false && killall Finder"
alias showdesktop="defaults write com.apple.finder CreateDesktop -bool true && killall Finder"

# PlistBuddy alias, because sometimes `defaults` just doesn’t cut it
alias plistbuddy="/usr/libexec/PlistBuddy"

# Pretty JSON
alias prettyjson='python -m json.tool'

# Kubernetes
alias kube='kubectl'
alias k='kubectl'

#Docker
alias d='docker'
alias dc='docker compose'

# .mov to .gif
mov2gif() {
	input="$1"
	filename="${input%%.*}"
	ffmpeg -i "$input" -pix_fmt rgb24 -r 15 -f gif - | gifsicle --threads=8 --lossy=50 --optimize=3 --delay=3 >"$filename.gif"
}

# tsx
alias tsx="npx tsx"

# Read node dependencies
alias deps='jq .dependencies < package.json'
alias devdeps='jq .devDependencies < package.json'
alias scripts='jq .scripts < package.json'
alias s='scripts'

# Windows WSL
if [[ $(uname -a) =~ "WSL2" ]]; then
	alias open='explorer.exe $1'
	function fork() {
		arg=$1
		if [[ -z "$arg" ]]; then
			arg=$(wslpath -w $PWD)
		fi
		/mnt/c/Users/$USER/AppData/Local/Fork/Fork.exe "$arg"
	}
fi
