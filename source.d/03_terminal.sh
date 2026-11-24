# ==============================================================================
# D-BUS PERFORMANCE & TERMINAL STATE RULES
# ==============================================================================

# Terminal control helpers (tput with ANSI fallbacks, set -e safe)
_term_alt_enter() {
    tput smcup 2>/dev/null || printf '\033[?1049h' || true
}

_term_alt_exit() {
    tput rmcup 2>/dev/null || printf '\033[?1049l' || true
}

_term_cursor_hide() {
    tput civis 2>/dev/null || printf '\033[?25l' || true
}

_term_cursor_show() {
    tput cnorm 2>/dev/null || printf '\033[?25h' || true
}

# Capture terminal settings, buffer stderr, and enter alternate screen buffer.
# Must only be called after CLI parsing and pre-flight validations succeed.
enter_tui_mode() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        return 0
    fi

    ORIG_STTY=$(stty -g 2>/dev/null || true)

    # Buffer stderr while inside the alternate screen so crash messages survive rmcup
    if [[ -t 2 ]]; then
        _TUI_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/service_manager_err.XXXXXX" 2>/dev/null || true)
        if [[ -n "$_TUI_ERR_FILE" ]]; then
            exec {_TUI_ORIG_STDERR_FD}>&2
            exec 2>"$_TUI_ERR_FILE"
            _TUI_STDERR_REDIRECTED=1
        fi
    fi

    _term_alt_enter
    _term_cursor_hide
    _TUI_ALT_SCREEN_ACTIVE=1

    # Non-Canonical Terminal Input: Preserve newline translation
    stty -icanon -echo min 1 time 0 2>/dev/null || true

    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    TERM_LINES=$(tput lines 2>/dev/null || echo 24)
}

# Record a fatal error message so cleanup() prints it after exiting alt screen.
tui_fatal() {
    local msg="$1"
    local rc="${2:-1}"
    _TUI_FATAL_ERROR="$msg"
    exit "$rc"
}

# Subcommand Context Wrapper: Restores cooked terminal and shows cursor
with_cooked_terminal() {
    local _restore_stderr=0
    if [[ -t 0 && -t 1 ]]; then
        if [[ -n "${ORIG_STTY:-}" ]]; then
            stty "$ORIG_STTY" 2>/dev/null || stty icanon echo 2>/dev/null || true
        else
            stty icanon echo 2>/dev/null || true
        fi
        _term_cursor_show
        # Restore stderr only when stdout is a tty (preserve caller redirections like 2>&1)
        if (( ${_TUI_STDERR_REDIRECTED:-0} == 1 )) && [[ -n "${_TUI_ERR_FILE:-}" ]]; then
            exec 2>&"${_TUI_ORIG_STDERR_FD}" || true
            _restore_stderr=1
        fi
    fi

    local exit_code=0
    "$@" || exit_code=$?

    if (( _restore_stderr == 1 )) && [[ -n "${_TUI_ERR_FILE:-}" ]]; then
        exec 2>>"${_TUI_ERR_FILE}" || true
    fi

    if [[ -t 0 && -t 1 ]]; then
        stty -icanon -echo min 1 time 0 2>/dev/null || true
        _term_cursor_hide
    fi

    return "$exit_code"
}

cleanup() {
    local exit_code=$?
    [[ "${_TUI_CLEANED_UP:-0}" -eq 1 ]] && return "$exit_code"
    _TUI_CLEANED_UP=1

    if [[ -t 0 && -t 1 ]] && (( ${_TUI_ALT_SCREEN_ACTIVE:-0} == 1 )); then
        # a. Restore cursor visibility
        _term_cursor_show
        # b. Exit alternate screen buffer
        _term_alt_exit
        # c. Restore saved terminal settings
        if [[ -n "${ORIG_STTY:-}" ]]; then
            stty "$ORIG_STTY" 2>/dev/null || true
        else
            stty icanon echo 2>/dev/null || true
        fi
        _TUI_ALT_SCREEN_ACTIVE=0
    fi

    # Restore original stderr before emitting any buffered crash diagnostics
    if (( ${_TUI_STDERR_REDIRECTED:-0} == 1 )); then
        exec 2>&"${_TUI_ORIG_STDERR_FD}" || true
        exec {_TUI_ORIG_STDERR_FD}>&- || true
        _TUI_STDERR_REDIRECTED=0
    fi

    if (( exit_code != 0 )) || [[ -n "${_TUI_FATAL_ERROR:-}" ]]; then
        if [[ -n "${_TUI_FATAL_ERROR:-}" ]]; then
            printf '%s\n' "$_TUI_FATAL_ERROR" >&2
        fi
        if [[ -n "${_TUI_ERR_FILE:-}" && -s "$_TUI_ERR_FILE" ]]; then
            cat "$_TUI_ERR_FILE" >&2
        fi
    fi

    # d. Remove temporary stderr buffer
    if [[ -n "${_TUI_ERR_FILE:-}" ]]; then
        rm -f "$_TUI_ERR_FILE" 2>/dev/null || true
        _TUI_ERR_FILE=""
    fi

    return "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

audit_log() {
    local action="$1"
    local target="$2"
    local result="$3"
    local details="${4:-}"

    if (( FLAG_NO_LOG == 1 )); then
        return 0
    fi

    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] ACTION="%s" TARGET="%s" RESULT="%s" DETAILS="%s"\n' \
        "$timestamp" "$action" "$target" "$result" "$details" >> "$LOG_FILE" 2>/dev/null || true
}
