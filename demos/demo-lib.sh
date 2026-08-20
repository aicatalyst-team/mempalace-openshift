#!/bin/bash
#
# Demo Library - Reusable Functions for Hermes/MemPalace Demos
# Based on proof-of-concept/demo pattern
#
# Author: Gerald Trotman (Red Hat)
# Date: June 2, 2026
# Usage: source ./demo-lib.sh in your demo scripts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Demo timing (adjust for presentation speed)
ACT_PAUSE=${ACT_PAUSE:-8}          # Seconds to show act header
SECTION_PAUSE=${SECTION_PAUSE:-5}  # Seconds between sections
COMMAND_PAUSE=${COMMAND_PAUSE:-3}  # Seconds before executing command
RESULT_PAUSE=${RESULT_PAUSE:-7}    # Seconds to show results
TYPE_SPEED=${TYPE_SPEED:-0.08}     # Seconds per character for typing effect

# Helper functions
slow_type() {
    local text="$1"
    local delay="${2:-$TYPE_SPEED}"
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

section_header() {
    local title="$1"
    echo ""
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}${title}${NC}"
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    demo_wait "$SECTION_PAUSE"
}

act() {
    local number="$1"
    local title="$2"
    # Clear only if terminal is available
    if [ -t 1 ] && [ -n "$TERM" ]; then
        clear
    fi
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║                                                                   ║${NC}"
    echo -e "${YELLOW}║   ${WHITE}ACT ${number}: ${title}${YELLOW}$(printf '%*s' $((53 - ${#title})) '')║${NC}"
    echo -e "${YELLOW}║                                                                   ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    demo_wait "$ACT_PAUSE"
}

run_command() {
    local cmd="$1"
    local description="$2"
    local output_limit="${3:-50}"  # Default limit to 50 lines

    if [ -n "$description" ]; then
        echo -e "${CYAN}# $description${NC}"
    fi
    echo -e "${GREEN}\$ ${cmd}${NC}"
    demo_wait "$COMMAND_PAUSE"
    eval "$cmd" 2>&1 | head -"$output_limit"
    echo ""
    demo_wait "$RESULT_PAUSE"
}

simulate_typing() {
    local cmd="$1"
    echo -n -e "${GREEN}\$ ${NC}"
    slow_type "$cmd" 0.05
    sleep 0.5
}

show_result() {
    local status="$1"
    local message="$2"

    if [ "$status" = "success" ]; then
        echo -e "${GREEN}✓ ${message}${NC}"
    elif [ "$status" = "error" ]; then
        echo -e "${RED}✗ ${message}${NC}"
    elif [ "$status" = "info" ]; then
        echo -e "${CYAN}ℹ ${message}${NC}"
    elif [ "$status" = "warning" ]; then
        echo -e "${YELLOW}⚠ ${message}${NC}"
    fi
    echo ""
}

pause() {
    echo -e "${CYAN}Press ENTER to continue...${NC}"
    read -r
}

demo_wait() {
    if [ "${STEP_MODE:-0}" = "1" ]; then
        echo -e "${CYAN}▶ Press ENTER to continue...${NC}"
        read -r
        # Clear the prompt line so it doesn't clutter the recording
        printf '\033[1A\033[2K'
    else
        sleep "${1:-5}"
    fi
}

demo_intro() {
    local title="$1"
    local subtitle="$2"
    local presenter="$3"

    # Clear only if terminal is available
    if [ -t 1 ] && [ -n "$TERM" ]; then
        clear
    fi
    cat << EOF

╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║                ${title}                ║
║                                                                   ║
║                  ${subtitle}                   ║
║                                                                   ║
║  Presented by: ${presenter}                              ║
║  Date:         $(date +"%B %d, %Y")                                       ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF
    demo_wait 3
}

highlight() {
    local text="$1"
    echo -e "${WHITE}${text}${NC}"
}

bullet() {
    local text="$1"
    echo -e "  ${GREEN}• ${text}${NC}"
}

# Verify prerequisites
check_prereq() {
    local cmd="$1"
    local name="$2"

    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}✗ ${name} not found (${cmd})${NC}"
        return 1
    else
        echo -e "${GREEN}✓ ${name} available${NC}"
        return 0
    fi
}

# Display a box with ASCII art
draw_box() {
    local width=67
    local text="$1"
    local padding=$(( (width - ${#text}) / 2 ))

    echo -e "${YELLOW}╔$(printf '═%.0s' $(seq 1 $width))╗${NC}"
    echo -e "${YELLOW}║$(printf ' %.0s' $(seq 1 $width))║${NC}"
    echo -e "${YELLOW}║$(printf ' %.0s' $(seq 1 $padding))${WHITE}${text}${YELLOW}$(printf ' %.0s' $(seq 1 $((width - padding - ${#text}))))║${NC}"
    echo -e "${YELLOW}║$(printf ' %.0s' $(seq 1 $width))║${NC}"
    echo -e "${YELLOW}╚$(printf '═%.0s' $(seq 1 $width))╝${NC}"
}

# Display a countdown
countdown() {
    local seconds="$1"
    local message="$2"

    echo -e "${CYAN}${message}${NC}"
    for i in $(seq "$seconds" -1 1); do
        echo -ne "${YELLOW}${i}...${NC}\r"
        sleep 1
    done
    echo -e "${GREEN}Go!${NC}"
    echo ""
}
