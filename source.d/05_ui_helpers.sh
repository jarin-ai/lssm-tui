# ==============================================================================
# UI FRAME BOX HELPERS (UTF-8 SAFE)
# ==============================================================================

print_box_top() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_TL" "$HBAR" "$BOX_TR" "$COLOR_RESET"
}

print_box_divider() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_ML" "$HBAR" "$BOX_MR" "$COLOR_RESET"
}

print_box_bottom() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_BL" "$HBAR" "$BOX_BR" "$COLOR_RESET"
}

print_box_line() {
    local text="$1"
    local color="${2:-$COLOR_TEXT}"
    if (( ${#text} > INNER_WIDTH )); then
        text="${text:0:$INNER_WIDTH}"
    fi
    local pad_len=$(( INNER_WIDTH - ${#text} ))
    local spaces=""
    if (( pad_len > 0 )); then
        printf -v spaces "%*s" "$pad_len" ""
    fi
    printf '%s%s%s%s%s%s%s%s%s%s\n' \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
        "$color" "$text" "$COLOR_RESET" \
        "$spaces" \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
}
