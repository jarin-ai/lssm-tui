# shellcheck shell=bash
# ==============================================================================
# TERMINAL STATE, CLEANUP REGISTRY & AUDIT LOGGING
# ==============================================================================

_TERM_ORIG_STTY=""
_TERM_ALT_SCREEN_ACTIVE=0
_TERM_CLEANED_UP=0
_TERM_ERR_FILE=""
_TERM_ORIG_STDERR_FD=""
_TERM_STDERR_REDIRECTED=0
_TERM_CLEANUP_CALLBACKS=()

_term__alt_enter() {
    tput smcup 2>/dev/null || printf '\033[?1049h' || true
}

_term__alt_exit() {
    tput rmcup 2>/dev/null || printf '\033[?1049l' || true
}

_term__cursor_hide() {
    tput civis 2>/dev/null || printf '\033[?25l' || true
}

_term__cursor_show() {
    tput cnorm 2>/dev/null || printf '\033[?25h' || true
}

# Query terminal row count and update STATE_TERM_LINES.
# Inputs: none
# Outputs: updates STATE_TERM_LINES via state__set_term_lines
# Returns: 0
term__refresh_size() {
    local size_str=""
    local rows=""

    if size_str=$(stty size 2>/dev/null); then
        read -r rows _ <<< "$size_str" || true
    fi

    if [[ ! "$rows" =~ ^[0-9]+$ ]] || (( rows <= 0 )); then
        rows=$(tput lines 2>/dev/null || true)
    fi

    if [[ ! "$rows" =~ ^[0-9]+$ ]] || (( rows <= 0 )); then
        rows=24
    fi

    state__set_term_lines "$rows"
}

# Return 0 if alternate screen buffer is active, 1 otherwise.
# Inputs: none
# Outputs: none
# Returns: 0 if active, 1 otherwise
term__is_alt_screen_active() {
    (( _TERM_ALT_SCREEN_ACTIVE == 1 ))
}

# Capture terminal settings, buffer stderr, and enter alternate screen buffer.
# Must only be called after CLI parsing and pre-flight validations succeed.
# Inputs: none
# Outputs: modifies terminal state and stderr FD
# Returns: 0
term__enter_tui_mode() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        return 0
    fi

    _TERM_ORIG_STTY=$(stty -g 2>/dev/null || true)

    # Buffer stderr while inside the alternate screen so crash messages survive rmcup
    if [[ -t 2 ]]; then
        _TERM_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/service_manager_err.XXXXXX" 2>/dev/null || true)
        if [[ -n "$_TERM_ERR_FILE" ]]; then
            exec {_TERM_ORIG_STDERR_FD}>&2
            exec 2>"$_TERM_ERR_FILE"
            _TERM_STDERR_REDIRECTED=1
        fi
    fi

    _term__alt_enter
    _term__cursor_hide
    _TERM_ALT_SCREEN_ACTIVE=1

    # Non-Canonical Terminal Input: Preserve newline translation
    stty -icanon -echo min 1 time 0 2>/dev/null || true

    term__refresh_size
}

# Run a command with cooked terminal settings and visible cursor, then restore raw TUI mode.
# Inputs: $@=command and arguments
# Outputs: command stdout/stderr
# Returns: command's exit code
term__with_cooked_terminal() {
    local restore_stderr=0
    if [[ -t 0 && -t 1 ]]; then
        if [[ -n "$_TERM_ORIG_STTY" ]]; then
            stty "$_TERM_ORIG_STTY" 2>/dev/null || stty icanon echo 2>/dev/null || true
        else
            stty icanon echo 2>/dev/null || true
        fi
        _term__cursor_show
        # Restore stderr only when stdout is a tty (preserve caller redirections like 2>&1)
        if (( _TERM_STDERR_REDIRECTED == 1 )) && [[ -n "$_TERM_ERR_FILE" ]]; then
            exec 2>&"${_TERM_ORIG_STDERR_FD}" || true
            restore_stderr=1
        fi
    fi

    local exit_code=0
    "$@" || exit_code=$?

    if (( restore_stderr == 1 )) && [[ -n "$_TERM_ERR_FILE" ]]; then
        exec 2>>"$_TERM_ERR_FILE" || true
    fi

    if [[ -t 0 && -t 1 ]]; then
        stty -icanon -echo min 1 time 0 2>/dev/null || true
        _term__cursor_hide
    fi

    return "$exit_code"
}

# Register a cleanup callback to run on EXIT (executed in reverse registration order).
# Inputs: $1=callback function name
# Outputs: none
# Returns: 0
term__register_cleanup() {
    local callback="$1"
    _TERM_CLEANUP_CALLBACKS+=("$callback")
}

# Execute all registered cleanup callbacks safely while preserving the exit status.
# Inputs: none (captures $?)
# Outputs: none
# Returns: original exit status
term__run_cleanups() {
    local exit_code=$?
    local idx=$(( ${#_TERM_CLEANUP_CALLBACKS[@]} - 1 ))

    while (( idx >= 0 )); do
        "${_TERM_CLEANUP_CALLBACKS[idx]}" "$exit_code" || true
        idx=$(( idx - 1 ))
    done

    return "$exit_code"
}

# Idempotent terminal and stderr restoration callback.
# Inputs: $1=exit_code (optional, defaults to 0)
# Outputs: buffered stderr diagnostics on non-zero exit
# Returns: 0
term__cleanup() {
    local exit_code="${1:-0}"
    if (( _TERM_CLEANED_UP == 1 )); then
        return 0
    fi
    _TERM_CLEANED_UP=1

    if [[ -t 0 && -t 1 ]] && (( _TERM_ALT_SCREEN_ACTIVE == 1 )); then
        _term__cursor_show
        _term__alt_exit
        if [[ -n "$_TERM_ORIG_STTY" ]]; then
            stty "$_TERM_ORIG_STTY" 2>/dev/null || true
        else
            stty icanon echo 2>/dev/null || true
        fi
        _TERM_ALT_SCREEN_ACTIVE=0
    fi

    # Restore original stderr before emitting any buffered crash diagnostics
    if (( _TERM_STDERR_REDIRECTED == 1 )); then
        exec 2>&"${_TERM_ORIG_STDERR_FD}" || true
        exec {_TERM_ORIG_STDERR_FD}>&- || true
        _TERM_STDERR_REDIRECTED=0
    fi

    if (( exit_code != 0 )) && [[ -n "$_TERM_ERR_FILE" && -s "$_TERM_ERR_FILE" ]]; then
        local err_line=""
        while IFS= read -r err_line || [[ -n "$err_line" ]]; do
            printf '%s\n' "$err_line" >&2
        done < "$_TERM_ERR_FILE"
    fi

    if [[ -n "$_TERM_ERR_FILE" ]]; then
        rm -f "$_TERM_ERR_FILE" 2>/dev/null || true
        _TERM_ERR_FILE=""
    fi

    return 0
}

# Append a structured audit entry to LOG_FILE unless logging is disabled.
# Inputs: $1=action, $2=target, $3=result, $4=details (optional)
# Outputs: appends line to LOG_FILE
# Returns: 0
audit__log() {
    local action="$1"
    local target="$2"
    local result="$3"
    local details="${4:-}"

    if (( _CLI_NO_LOG == 1 )); then
        return 0
    fi

    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local timestamp=""
    printf -v timestamp '%(%Y-%m-%d %H:%M:%S)T' -1
    printf '[%s] ACTION="%s" TARGET="%s" RESULT="%s" DETAILS="%s"\n' \
        "$timestamp" "$action" "$target" "$result" "$details" >> "$LOG_FILE" 2>/dev/null || true
}
