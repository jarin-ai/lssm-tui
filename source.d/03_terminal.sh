# ==============================================================================
# D-BUS PERFORMANCE & TERMINAL STATE RULES
# ==============================================================================

# Subcommand Context Wrapper: Restores cooked terminal and shows cursor
with_cooked_terminal() {
    if [[ -n "${SAVED_TTY_SETTINGS:-}" ]]; then
        stty "$SAVED_TTY_SETTINGS" 2>/dev/null || stty icanon echo 2>/dev/null || true
    else
        stty icanon echo 2>/dev/null || true
    fi
    printf '%s' "$TERM_CURSOR_SHOW"

    local exit_code=0
    "$@" || exit_code=$?

    stty -icanon -echo min 1 time 0 2>/dev/null || true
    printf '%s' "$TERM_CURSOR_HIDE"

    return "$exit_code"
}

cleanup() {
    printf '%s' "$TERM_CURSOR_SHOW"
    if [[ -n "${SAVED_TTY_SETTINGS:-}" ]]; then
        stty "$SAVED_TTY_SETTINGS" 2>/dev/null || true
    else
        stty icanon echo 2>/dev/null || true
    fi
    printf '\n'
}
trap cleanup EXIT INT TERM HUP

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
