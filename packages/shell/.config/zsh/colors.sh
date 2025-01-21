colorize() {
	printf "\x1b[${1}m"
}

section_header() {
	echo "$(blue '==>') $(purple "${1}")"
}

NC=$(colorize '0') # No Color
BLACK=$(colorize '0;30')
DARK_GRAY=$(colorize '1;30')
RED=$(colorize '0;31')
LIGHT_RED=$(colorize '1;31')
GREEN=$(colorize '0;32')
LIGHT_GREEN=$(colorize '1;32')
ORANGE=$(colorize '0;33')
YELLOW=$(colorize '1;33')
BLUE=$(colorize '0;34')
LIGHT_BLUE=$(colorize '1;34')
PURPLE=$(colorize '0;35')
LIGHT_PURPLE=$(colorize '1;35')
CYAN=$(colorize '0;36')
LIGHT_CYAN=$(colorize '1;36')
LIGHT_GRAY=$(colorize '0;37')
WHITE=$(colorize '1;37')

blue() {
	printf "${BLUE}${1}${NC}"
}

light_blue() {
	printf "${LIGHT_BLUE}${1}${NC}"
}

purple() {
	printf "${PURPLE}${1}${NC}"
}

light_purple() {
	printf "${LIGHT_PURPLE}${1}${NC}"
}

cyan() {
	printf "${CYAN}${1}${NC}"
}

light_cyan() {
	printf "${LIGHT_CYAN}${1}${NC}"
}

green() {
	printf "${GREEN}${1}${NC}"
}

light_green() {
	printf "${LIGHT_GREEN}${1}${NC}"
}

red() {
	printf "${RED}${1}${NC}"
}

light_red() {
	printf "${LIGHT_RED}${1}${NC}"
}

yellow() {
	printf "${YELLOW}${1}${NC}"
}

warn() {
	echo "$(yellow "**WARN** ${1}")"
}

success() {
	echo "$(green "**SUCCESS** ${1}")"
}

debug() {
	warn "${1}"
	echo "${PATH}"
}

error() {
	echo "$(red "${1}")"
	exit 1
}

section_header() {
	echo "$(blue '==>') $(purple "${1}")"
}
