# ==============================================================================
# KEYBINDINGS & CONTROL LOGIC
# ==============================================================================

read_key() {
    local k=""
    IFS= read -rsn1 k || return 1
    if [[ "$k" == $'\x1b' ]]; then
        local seq=""
        IFS= read -rsn1 -t 0.05 seq || true
        if [[ -z "$seq" ]]; then
            echo "ESC"
            return 0
        fi
        if [[ "$seq" == "[" ]]; then
            local code=""
            IFS= read -rsn1 -t 0.05 code || true
            case "$code" in
                A) echo "UP"; return 0 ;;
                B) echo "DOWN"; return 0 ;;
                C) echo "RIGHT"; return 0 ;;
                D) echo "LEFT"; return 0 ;;
                Z) echo "BTAB"; return 0 ;;
                *) echo "ESC"; return 0 ;;
            esac
        fi
        echo "ESC"
        return 0
    elif [[ -z "$k" || "$k" == $'\n' || "$k" == $'\r' ]]; then
        echo "ENTER"
        return 0
    elif [[ "$k" == $'\t' ]]; then
        echo "TAB"
        return 0
    elif [[ "$k" == $'\x7f' || "$k" == $'\x08' ]]; then
        echo "BACKSPACE"
        return 0
    else
        echo "$k"
        return 0
    fi
}

handle_resize() {
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    TERM_LINES=$(tput lines 2>/dev/null || echo 24)
    printf '%s%s' "$TERM_CLEAR_SCREEN" "$TERM_CURSOR_HOME"
    draw_ui
}
trap handle_resize WINCH
