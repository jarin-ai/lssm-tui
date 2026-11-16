# ==============================================================================
# TUI SCREEN LAYOUT STRUCTURE RENDERING
# ==============================================================================

get_hint_text() {
    if (( SEARCH_MODE == 1 )); then
        echo "Type query. Press [Enter] to finish search, [ESC] to cancel filter."
        return
    fi
    if (( HELP_MODE == 1 )); then
        echo "Press [h] or [ESC] to exit cheat sheet and return to service list."
        return
    fi
    if [[ "$FOCUS_AREA" == "system" ]]; then
        case "$SYS_BTN" in
            0) echo "Press [Enter] to enter Search Mode (or press '/')." ;;
            1) echo "Press [Enter] to view keybinding cheat sheet (or press 'h')." ;;
            2) echo "Press [Enter] to clear config & logs (or press 'c')." ;;
        esac
        return
    fi

    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
        echo "No matching services. Press [ESC] to clear search filter."
        return
    fi

    local current_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
    case "$SELECTED_BTN" in
        0)
            local a_state="${SVC_ACTIVE_STATE[$current_svc]:-inactive}"
            if [[ "$a_state" == "active" ]]; then
                echo "Press [Enter] to stop '${current_svc}' (requires confirmation). [g/Home] to jump to action bar."
            else
                echo "Press [Enter] to start '${current_svc}'. [g/Home] to jump to action bar."
            fi
            ;;
        1)
            echo "Press [Enter] to restart '${current_svc}'. [g/Home] to jump to action bar."
            ;;
        2)
            local u_state="${SVC_UNIT_STATE[$current_svc]:-disabled}"
            if [[ "$u_state" == "enabled" ]]; then
                echo "Press [Enter] to disable '${current_svc}' (requires confirmation). [g/Home] to jump to action bar."
            else
                echo "Press [Enter] to enable '${current_svc}' on boot. [g/Home] to jump to action bar."
            fi
            ;;
    esac
}

render_cheat_sheet() {
    local cheat_lines=(
        "  KEYBOARD SHORTCUT CHEAT SHEET"
        "  ────────────────────────────────────────────────────────────────────────"
        "  [↑ / ↓]       Navigate service rows or switch to system action bar"
        "  [← / →]       Navigate action buttons across highlighted service row"
        "  [Enter]       Execute highlighted action (confirms stop/disable)"
        "  [g / Home]    Jump to system action bar (top command line)"
        "  [/]           Enter Search Mode (filters services by name & description)"
        "  [h / H]       Toggle this keybinding cheat sheet"
        "  [c / C]       Clear config and audit logs (prompts confirmation)"
        "  [d / D]       Toggle Information Area (Description <-> CPU/Memory/PID)"
        "  [l / L]       Open journalctl log viewer modal (last 30 entries)"
        "  [i / I]       Open systemctl status inspection modal"
        "  [r / R]       Manually refresh systemd cache and process metrics"
        "  [ESC]         Exit active search / close cheat sheet / cancel filter"
        "  [q / Q]       Cleanly exit service manager"
    )
    for cline in "${cheat_lines[@]}"; do
        print_box_line "$cline" "$COLOR_SECONDARY"
    done
}

draw_ui() {
    # Move to Home without clearing to eliminate screen flicker
    printf '%s' "$TERM_CURSOR_HOME"

    # 1. Application Title Banner (Very Top)
    print_box_top
    local title_str="Linux systemctl manager"
    local left_pad=$(( (INNER_WIDTH - ${#title_str}) / 2 ))
    local right_pad=$(( INNER_WIDTH - ${#title_str} - left_pad ))
    local p_title
    printf -v p_title "%*s%s%*s" "$left_pad" "" "$title_str" "$right_pad" ""
    print_box_line "$p_title" "$COLOR_TITLE$COLOR_BOLD"

    # Divider below Title
    print_box_divider

    # 2. System Action Bar (Below Title)
    if (( SEARCH_MODE == 1 )); then
        local search_prefix="  Search: "
        local cursor_sym="_"
        local used_len=$(( ${#search_prefix} + ${#SEARCH_QUERY} + ${#cursor_sym} ))
        local fill_len=$(( INNER_WIDTH - used_len ))
        (( fill_len < 0 )) && fill_len=0
        local pad_fill
        printf -v pad_fill "%*s" "$fill_len" ""
        local search_line="  ${COLOR_ACCENT}Search: ${COLOR_RESET}${COLOR_BOLD}${COLOR_TEXT}${SEARCH_QUERY}${COLOR_PRIMARY}_${COLOR_RESET}${pad_fill}"
        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$search_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    else
        local btn_search_style="$COLOR_ACCENT"
        local btn_help_style="$COLOR_ACCENT"
        local btn_clear_style="$COLOR_ACCENT"

        if [[ "$FOCUS_AREA" == "system" ]]; then
            (( SYS_BTN == 0 )) && btn_search_style="$COLOR_HIGHLIGHT" || btn_search_style="$COLOR_PRIMARY"
            (( SYS_BTN == 1 )) && btn_help_style="$COLOR_HIGHLIGHT" || btn_help_style="$COLOR_PRIMARY"
            (( SYS_BTN == 2 )) && btn_clear_style="$COLOR_HIGHLIGHT" || btn_clear_style="$COLOR_PRIMARY"
        fi

        local plain_len=41 # "  Actions:  [search]    [help]    [clear]"
        local pad_sys_len=$(( INNER_WIDTH - plain_len ))
        local pad_sys
        printf -v pad_sys "%*s" "$pad_sys_len" ""
        local sys_line="  Actions:  ${btn_search_style}[search]${COLOR_RESET}    ${btn_help_style}[help]${COLOR_RESET}    ${btn_clear_style}[clear]${COLOR_RESET}${pad_sys}"

        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$sys_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    fi

    # Divider below System Action Bar
    print_box_divider

    # 3. Service List Area (Middle Main Area)
    if (( HELP_MODE == 1 )); then
        render_cheat_sheet
    else
        # Column Header Row
        local p_hdr_name p_hdr_active p_hdr_btn1 p_hdr_btn2 p_hdr_unit p_hdr_btn3
        printf -v p_hdr_name "%-16.16s" "SERVICE"
        printf -v p_hdr_active "%-12.12s" "STATE"
        printf -v p_hdr_btn1 "%-9.9s" "ACTION 1"
        printf -v p_hdr_btn2 "%-11.11s" "RESTART"
        printf -v p_hdr_unit "%-11.11s" "STARTUP"
        printf -v p_hdr_btn3 "%-9.9s" "ACTION 2"

        local hdr_content="  ${p_hdr_name} ${p_hdr_active} ${p_hdr_btn1} ${p_hdr_btn2} ${p_hdr_unit} ${p_hdr_btn3} "
        print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

        # Calculate visible rows and scroll window
        local available_rows=$(( TERM_LINES - 15 ))
        (( available_rows < 5 )) && available_rows=5
        (( available_rows > 15 )) && available_rows=15

        if (( SELECTED_ROW < SCROLL_OFFSET )); then
            SCROLL_OFFSET=$SELECTED_ROW
        elif (( SELECTED_ROW >= SCROLL_OFFSET + available_rows )); then
            SCROLL_OFFSET=$(( SELECTED_ROW - available_rows + 1 ))
        fi

        local total_visible=${#VISIBLE_SERVICES[@]}
        if (( total_visible == 0 )); then
            print_box_line "  (No services match search filter)" "$COLOR_MUTED"
            for (( r=1; r < available_rows; r++ )); do
                print_box_line "" "$COLOR_TEXT"
            done
        else
            for (( idx=0; idx < available_rows; idx++ )); do
                local service_idx=$(( SCROLL_OFFSET + idx ))
                if (( service_idx < total_visible )); then
                    local svc="${VISIBLE_SERVICES[$service_idx]}"
                    local a_state="${SVC_ACTIVE_STATE[$svc]:-unknown}"
                    local u_state="${SVC_UNIT_STATE[$svc]:-unknown}"

                    local btn1_label="[start]"
                    [[ "$a_state" == "active" ]] && btn1_label="[stop]"

                    local btn2_label="[restart]"

                    local btn3_label="[enable]"
                    [[ "$u_state" == "enabled" ]] && btn3_label="[disable]"

                    # ANSI Padding Rule: ALWAYS pad plain text with printf BEFORE applying semantic colors
                    local pad_svc pad_act pad_b1 pad_b2 pad_unt pad_b3
                    printf -v pad_svc "%-16.16s" "$svc"
                    printf -v pad_act "%-12.12s" "$a_state"
                    printf -v pad_b1 "%-9.9s" "$btn1_label"
                    printf -v pad_b2 "%-11.11s" "$btn2_label"
                    printf -v pad_unt "%-11.11s" "$u_state"
                    printf -v pad_b3 "%-9.9s" "$btn3_label"

                    # Apply semantic color styling
                    local col_svc="$COLOR_TEXT"
                    local is_row_active=0
                    if [[ "$FOCUS_AREA" == "services" ]] && (( service_idx == SELECTED_ROW )); then
                        is_row_active=1
                        col_svc="${COLOR_BOLD}${COLOR_TEXT}"
                    fi

                    local col_act="$COLOR_MUTED"
                    if [[ "$a_state" == "active" ]]; then
                        col_act="$COLOR_SUCCESS"
                    elif [[ "$a_state" == "failed" ]]; then
                        col_act="${COLOR_ERROR}${COLOR_BOLD}"
                    elif [[ "$a_state" =~ ^(activating|reloading|deactivating)$ ]]; then
                        col_act="$COLOR_WARN"
                    fi

                    local col_unt="$COLOR_MUTED"
                    if [[ "$u_state" == "enabled" ]]; then
                        col_unt="$COLOR_SUCCESS"
                    elif [[ "$u_state" == "masked" ]]; then
                        col_unt="$COLOR_ERROR"
                    elif [[ "$u_state" =~ ^(static|indirect)$ ]]; then
                        col_unt="$COLOR_WARN"
                    fi

                    local col_b1="$COLOR_PRIMARY"
                    local col_b2="$COLOR_PRIMARY"
                    local col_b3="$COLOR_PRIMARY"

                    if (( is_row_active == 1 )); then
                        (( SELECTED_BTN == 0 )) && col_b1="$COLOR_HIGHLIGHT"
                        (( SELECTED_BTN == 1 )) && col_b2="$COLOR_HIGHLIGHT"
                        (( SELECTED_BTN == 2 )) && col_b3="$COLOR_HIGHLIGHT"
                    fi

                    local row_colored="  ${col_svc}${pad_svc}${COLOR_RESET} ${col_act}${pad_act}${COLOR_RESET} ${col_b1}${pad_b1}${COLOR_RESET} ${col_b2}${pad_b2}${COLOR_RESET} ${col_unt}${pad_unt}${COLOR_RESET} ${col_b3}${pad_b3}${COLOR_RESET} "
                    printf '%s%s%s%s%s%s%s\n' \
                        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
                        "$row_colored" \
                        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
                else
                    print_box_line "" "$COLOR_TEXT"
                fi
            done
        fi
    fi

    # Divider below Service List Area
    print_box_divider

    # 4. Information Area (Below Service List) — hidden when cheat sheet is active
    if (( HELP_MODE == 0 )); then
        local info_text=""
        if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
            local cur_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
            if (( INFO_MODE == 0 )); then
                info_text="  Description: ${SVC_DESCRIPTION[$cur_svc]:-No description available}"
            else
                local cpu_val="${CPU_USAGE[$cur_svc]:-0.0}"
                local mem_val="${MEM_USAGE[$cur_svc]:-0.0}"
                local pid_val="${SVC_PID[$cur_svc]:-0}"
                [[ "$pid_val" == "0" ]] && pid_val="None"
                info_text="  Resource Usage: CPU: ${cpu_val}% | Memory: ${mem_val} MB | PID: ${pid_val}"
            fi
        else
            info_text="  Information: No service selected"
        fi
        print_box_line "$info_text" "$COLOR_ACCENT"

        # Divider below Information Area
        print_box_divider
    fi

    # 5. Hint Area (Below Information Area)
    local hint_text="  Hint: $(get_hint_text)"
    print_box_line "$hint_text" "$COLOR_MUTED"

    # Divider below Hint Area
    print_box_divider

    # 6. Status Bar (Bottom Row)
    local col_status="$COLOR_PRIMARY"
    if [[ "$CURRENT_STATUS" =~ "Success" ]]; then
        col_status="$COLOR_SUCCESS"
    elif [[ "$CURRENT_STATUS" =~ "Error" ]]; then
        col_status="${COLOR_ERROR}${COLOR_BOLD}"
    fi
    print_box_line "  ${CURRENT_STATUS}" "$col_status"

    # Bottom Frame Border
    print_box_bottom
}
