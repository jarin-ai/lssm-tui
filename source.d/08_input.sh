# shellcheck shell=bash
# ==============================================================================
# KEYBOARD INPUT DECODING & RESIZE HANDLING
# ==============================================================================

# Read and decode a single key or ANSI escape sequence into a nameref variable.
# Inputs: $1=nameref to output key string
# Outputs: sets referenced variable to decoded key token
# Returns: 0 on success, 1 on EOF/read failure
input__read_key() {
    local -n _irk_out="$1"
    local _irk_k=""
    IFS= read -rsn1 _irk_k || return 1

    if [[ "$_irk_k" == $'\x1b' ]]; then
        local _irk_seq=""
        IFS= read -rsn1 -t 0.05 _irk_seq || true
        if [[ -z "$_irk_seq" ]]; then
            _irk_out="ESC"
            return 0
        fi
        if [[ "$_irk_seq" == "[" ]]; then
            local _irk_code=""
            IFS= read -rsn1 -t 0.05 _irk_code || true
            case "$_irk_code" in
                A) _irk_out="UP" ;;
                B) _irk_out="DOWN" ;;
                C) _irk_out="RIGHT" ;;
                D) _irk_out="LEFT" ;;
                H) _irk_out="HOME" ;;
                F) _irk_out="END" ;;
                Z) _irk_out="IGNORE" ;;
                1|4|7|8)
                    local _irk_tilde=""
                    IFS= read -rsn1 -t 0.05 _irk_tilde || true
                    if [[ "$_irk_tilde" == "~" ]]; then
                        case "$_irk_code" in
                            1|7) _irk_out="HOME" ;;
                            4|8) _irk_out="END" ;;
                        esac
                    else
                        _irk_out="IGNORE"
                    fi
                    ;;
                *) _irk_out="ESC" ;;
            esac
            return 0
        elif [[ "$_irk_seq" == "O" ]]; then
            local _irk_code=""
            IFS= read -rsn1 -t 0.05 _irk_code || true
            case "$_irk_code" in
                A) _irk_out="UP" ;;
                B) _irk_out="DOWN" ;;
                C) _irk_out="RIGHT" ;;
                D) _irk_out="LEFT" ;;
                H) _irk_out="HOME" ;;
                F) _irk_out="END" ;;
                *) _irk_out="ESC" ;;
            esac
            return 0
        fi
        _irk_out="ESC"
        return 0
    elif [[ -z "$_irk_k" || "$_irk_k" == $'\n' || "$_irk_k" == $'\r' ]]; then
        _irk_out="ENTER"
        return 0
    elif [[ "$_irk_k" == $'\t' ]]; then
        _irk_out="TAB"
        return 0
    elif [[ "$_irk_k" == $'\x7f' || "$_irk_k" == $'\x08' ]]; then
        _irk_out="BACKSPACE"
        return 0
    else
        _irk_out="$_irk_k"
        return 0
    fi
}

# SIGWINCH handler: refresh terminal dimensions and redraw active TUI frame.
# Inputs: none
# Outputs: redraws TUI if alternate screen is active
# Returns: 0
input__handle_resize() {
    term__refresh_size
    if term__is_alt_screen_active; then
        printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
        draw__ui
    fi
}
