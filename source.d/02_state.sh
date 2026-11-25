# shellcheck shell=bash
# ==============================================================================
# STATE MANAGEMENT, DATA STRUCTURES & SHARED UTILITIES
# ==============================================================================

# --- Service & Script Data State ---
# shellcheck disable=SC2034
STATE_VISIBLE_SERVICES=()
# shellcheck disable=SC2034
STATE_SYSCTRL_SERVICES=()   # Loaded from systemctl list-unit-files
# shellcheck disable=SC2034
STATE_USER_SERVICES=()      # Loaded from config file (pinned services)
# shellcheck disable=SC2034
STATE_PINNED_COUNT=0        # Number of pinned services at top of STATE_VISIBLE_SERVICES

# shellcheck disable=SC2034
declare -A STATE_SVC_ACTIVE
# shellcheck disable=SC2034
declare -A STATE_SVC_UNIT
# shellcheck disable=SC2034
declare -A STATE_SVC_DESC
# shellcheck disable=SC2034
declare -A STATE_SVC_PID
# shellcheck disable=SC2034
declare -A STATE_CPU_USAGE
# shellcheck disable=SC2034
declare -A STATE_MEM_USAGE

# shellcheck disable=SC2034
STATE_CURRENT_VIEW="services"    # "services" or "scripts"
# shellcheck disable=SC2034
STATE_SCRIPTS_NAMES=()           # Script names defined in scripts.conf
# shellcheck disable=SC2034
STATE_SCRIPTS_PATHS=()           # Paths to .sh files, parallel to STATE_SCRIPTS_NAMES
# shellcheck disable=SC2034
STATE_VISIBLE_SCRIPTS=()         # Indices of scripts matching search query
# shellcheck disable=SC2034
STATE_SCRIPTS_ROW=0              # Selected row in scripts view
# shellcheck disable=SC2034
STATE_SCRIPTS_SCROLL_OFFSET=0    # Viewport scrolling offset for scripts

# --- UI Navigation & Viewport State ---
# shellcheck disable=SC2034
STATE_FOCUS_AREA="services"      # "services" or "system"
# shellcheck disable=SC2034
STATE_SYS_BTN=0                  # 0: [services], 1: [scripts], 2: [search], 3: [clear], 4: [help]
# shellcheck disable=SC2034
STATE_SELECTED_ROW=0             # Index within STATE_VISIBLE_SERVICES
# shellcheck disable=SC2034
STATE_SELECTED_BTN=0             # 0: [action1], 1: [restart], 2: [action2]
# shellcheck disable=SC2034
STATE_SCROLL_OFFSET=0            # Viewport scrolling offset
# shellcheck disable=SC2034
STATE_INFO_MODE=0                # 0: Description, 1: Live CPU/Memory
# shellcheck disable=SC2034
STATE_HELP_MODE=0                # 0: Normal service list, 1: Keybinding cheat sheet
# shellcheck disable=SC2034
STATE_HELP_SCROLL_OFFSET=0       # Scrolling offset for keybinding cheat sheet
# shellcheck disable=SC2034
STATE_SEARCH_MODE=0              # 0: Idle, 1: Active query typing
# shellcheck disable=SC2034
STATE_SEARCH_QUERY=""            # Current search string
# shellcheck disable=SC2034
STATE_CURRENT_STATUS="Status: Ready."

# --- Terminal Dimensions ---
# shellcheck disable=SC2034
STATE_TERM_LINES=24

# --- Shared Pure-Bash Utilities ---

# Trim leading and trailing whitespace from a variable in place.
# Inputs: $1=nameref to string variable
# Outputs: modifies referenced variable in place
# Returns: 0
util__trim() {
    local -n _ut_var="$1"
    _ut_var="${_ut_var#"${_ut_var%%[![:space:]]*}"}"
    _ut_var="${_ut_var%"${_ut_var##*[![:space:]]}"}"
}

# Compute the directory component of a path in pure Bash.
# Inputs: $1=file path, $2=nameref to output string
# Outputs: sets referenced variable to parent directory
# Returns: 0
util__dirname() {
    local _ud_path="$1"
    local -n _ud_out="$2"

    if [[ "$_ud_path" == */* ]]; then
        _ud_out="${_ud_path%/*}"
        if [[ -z "$_ud_out" ]]; then
            _ud_out="/"
        fi
    else
        _ud_out="."
    fi
}

# Compute clamped list height [5, 15] from terminal row count.
# Inputs: $1=terminal lines, $2=nameref to output integer
# Outputs: sets referenced variable to clamped row count
# Returns: 0
util__clamp_list_rows() {
    local _uc_term_lines="$1"
    local -n _uc_rows="$2"

    _uc_rows=$(( _uc_term_lines - 15 ))
    if (( _uc_rows < 5 )); then
        _uc_rows=5
    elif (( _uc_rows > 15 )); then
        _uc_rows=15
    fi
}

# Set the bottom status bar message.
# Inputs: $1=status text
# Outputs: updates STATE_CURRENT_STATUS
# Returns: 0
state__set_status() {
    # shellcheck disable=SC2034
    STATE_CURRENT_STATUS="$1"
}

# Update cached terminal row count.
# Inputs: $1=row count
# Outputs: updates STATE_TERM_LINES
# Returns: 0
state__set_term_lines() {
    # shellcheck disable=SC2034
    STATE_TERM_LINES="$1"
}

# Return 0 if the active view's visible list is empty, 1 otherwise.
# Inputs: none (reads STATE_CURRENT_VIEW, STATE_VISIBLE_SCRIPTS, STATE_VISIBLE_SERVICES)
# Outputs: none
# Returns: 0 if empty, 1 if non-empty
state__is_current_list_empty() {
    if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
        (( ${#STATE_VISIBLE_SCRIPTS[@]} == 0 ))
    else
        (( ${#STATE_VISIBLE_SERVICES[@]} == 0 ))
    fi
}
