# shellcheck shell=bash
# ==============================================================================
# UI FRAME BOX HELPERS (UTF-8 SAFE)
# ==============================================================================

# Print top rounded border of the TUI frame.
# Inputs: none
# Outputs: formatted border line on stdout
# Returns: 0
ui__print_box_top() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_TL" "$HBAR" "$BOX_TR" "$COLOR_RESET"
}

# Print horizontal divider line inside the TUI frame.
# Inputs: none
# Outputs: formatted divider line on stdout
# Returns: 0
ui__print_box_divider() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_ML" "$HBAR" "$BOX_MR" "$COLOR_RESET"
}

# Print bottom rounded border of the TUI frame.
# Inputs: none
# Outputs: formatted border line on stdout
# Returns: 0
ui__print_box_bottom() {
    printf '%s%s%s%s%s\n' "$COLOR_BORDER" "$BOX_BL" "$HBAR" "$BOX_BR" "$COLOR_RESET"
}

# Print a padded/truncated single-color line enclosed by vertical box borders.
# Inputs: $1=plain text, $2=ANSI color sequence (optional, defaults to COLOR_TEXT)
# Outputs: formatted frame row on stdout
# Returns: 0
ui__print_box_line() {
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

# Render modal footer prompt and wait for user to press Enter.
# Inputs: $1=prompt text (optional)
# Outputs: modal footer on stdout
# Returns: 0
ui__wait_modal_footer() {
    local prompt="${1:-  Press [Enter] to return...}"

    ui__print_box_divider
    ui__print_box_line "$prompt" "$COLOR_HIGHLIGHT$COLOR_BOLD"
    ui__print_box_bottom
    read -r _ || true
}
