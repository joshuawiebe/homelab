#!/usr/bin/env bash
# Shared logging module for all automation scripts
# Usage: source "$(dirname "$0")/../../../.shared/log.sh"

# Color codes
readonly COLOR_RESET='\033[0m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_PURPLE='\033[1;35m'

# Message functions
info() {
  echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

warn() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

success() {
  echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

error() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"
}

debug() {
  if [ "${DEBUG:-0}" = "1" ]; then
    echo -e "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $*"
  fi
}

# Header functions
section() {
  echo ""
  echo -e "${COLOR_PURPLE}============================================${COLOR_RESET}"
  echo -e "${COLOR_PURPLE}  $*${COLOR_RESET}"
  echo -e "${COLOR_PURPLE}============================================${COLOR_RESET}"
  echo ""
}

subsection() {
  echo -e "${COLOR_BOLD}$*${COLOR_RESET}"
  echo "─────────────────────────────────────────"
}

# Progress functions
progress_start() {
  local message="$1"
  info "$message"
}

progress_item() {
  local name="$1"
  local status="${2:-processing}"
  echo -e "  • $name: ${COLOR_YELLOW}$status${COLOR_RESET}"
}

progress_complete() {
  local total="$1"
  local completed="$2"
  success "$completed/$total items completed"
}

# Separator functions
separator() {
  echo "─────────────────────────────────────────"
}

separator_thick() {
  echo "==========================================="
}

# Exit functions
exit_success() {
  local message="${1:-Operation completed successfully}"
  echo ""
  success "$message"
  echo ""
  exit 0
}

exit_error() {
  local message="${1:-Operation failed}"
  local code="${2:-1}"
  echo ""
  error "$message"
  echo ""
  exit "$code"
}

# Confirmation function
confirm() {
  local prompt="$1"
  local response
  read -rp "$(echo -e ${COLOR_YELLOW}?) ${prompt} [y/N]: ${COLOR_RESET}" response
  [[ "$response" =~ ^[Yy]$ ]]
}

# Timer functions
timer_start() {
  TIMER_START=$(date +%s)
}

timer_end() {
  local end=$(date +%s)
  local duration=$((end - TIMER_START))
  info "Operation took ${duration}s"
}

# Export all functions
export -f info warn success error debug section subsection
export -f progress_start progress_item progress_complete
export -f separator separator_thick
export -f exit_success exit_error confirm
export -f timer_start timer_end
