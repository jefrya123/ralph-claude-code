#!/bin/bash

# Ralph Status Monitor - Live terminal dashboard for the Ralph loop
set -e

STATUS_FILE=".ralph/status.json"
LOG_FILE=".ralph/logs/ralph.log"
REFRESH_INTERVAL=2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Clear screen and hide cursor
clear_screen() {
    clear
    printf '\033[?25l'  # Hide cursor
}

# Show cursor on exit
show_cursor() {
    printf '\033[?25h'  # Show cursor
}

# Cleanup function
cleanup() {
    show_cursor
    echo
    echo "Monitor stopped."
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM EXIT

# Main display function
display_status() {
    clear_screen
    
    # Header
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                           🤖 RALPH MONITOR                              ║${NC}"
    echo -e "${WHITE}║                        Live Status Dashboard                           ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    # Status section
    if [[ -f "$STATUS_FILE" ]]; then
        # Parse JSON status
        local status_data=$(cat "$STATUS_FILE")
        local loop_count=$(echo "$status_data" | jq -r '.loop_count // "0"' 2>/dev/null || echo "0")
        local calls_made=$(echo "$status_data" | jq -r '.calls_made_this_hour // "0"' 2>/dev/null || echo "0")
        local max_calls=$(echo "$status_data" | jq -r '.max_calls_per_hour // "100"' 2>/dev/null || echo "100")
        local status=$(echo "$status_data" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
        
        echo -e "${CYAN}┌─ Current Status ────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${NC} Loop Count:     ${WHITE}#$loop_count${NC}"
        echo -e "${CYAN}│${NC} Status:         ${GREEN}$status${NC}"
        echo -e "${CYAN}│${NC} API Calls:      $calls_made/$max_calls"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        echo
        
    else
        echo -e "${RED}┌─ Status ────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${RED}│${NC} Status file not found. Ralph may not be running."
        echo -e "${RED}└─────────────────────────────────────────────────────────────────────────┘${NC}"
        echo
    fi
    
    # Plan Queue section (plan-dir mode)
    if [[ -f ".ralph/.plan_queue_status.json" ]]; then
        local pq_data=$(cat ".ralph/.plan_queue_status.json" 2>/dev/null)
        local pq_mode=$(echo "$pq_data" | jq -r '.mode // ""' 2>/dev/null || echo "")

        if [[ "$pq_mode" == "plan_queue" ]]; then
            local pq_progress=$(echo "$pq_data" | jq -r '.progress // "0/0"' 2>/dev/null || echo "0/0")
            local pq_current=$(echo "$pq_data" | jq -r '.current_plan // ""' 2>/dev/null || echo "")
            local pq_status=$(echo "$pq_data" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
            local pq_total=$(echo "$pq_data" | jq -r '.total // 0' 2>/dev/null || echo "0")

            echo -e "${PURPLE}┌─ Plan Queue ────────────────────────────────────────────────────────────┐${NC}"
            echo -e "${PURPLE}│${NC} Progress:       ${WHITE}$pq_progress${NC} plans completed"

            if [[ -n "$pq_current" && "$pq_current" != "null" && "$pq_current" != "" ]]; then
                local current_basename=$(basename "$pq_current")
                echo -e "${PURPLE}│${NC} Current Plan:   ${GREEN}$current_basename${NC}"
            fi

            echo -e "${PURPLE}│${NC} Status:         ${WHITE}$pq_status${NC}"

            # Show queue entries
            local queue_len=$(echo "$pq_data" | jq -r '.queue | length' 2>/dev/null || echo "0")
            if [[ "$queue_len" -gt 0 ]]; then
                echo -e "${PURPLE}│${NC}"
                for ((qi=0; qi<queue_len; qi++)); do
                    local qi_file=$(echo "$pq_data" | jq -r ".queue[$qi].file" 2>/dev/null)
                    local qi_status=$(echo "$pq_data" | jq -r ".queue[$qi].status" 2>/dev/null)
                    local qi_basename=$(basename "$qi_file")
                    local qi_icon="  "
                    case "$qi_status" in
                        completed)   qi_icon="${GREEN}✓${NC}" ;;
                        in_progress) qi_icon="${YELLOW}▶${NC}" ;;
                        pending)     qi_icon="${WHITE}○${NC}" ;;
                    esac
                    echo -e "${PURPLE}│${NC}   $qi_icon $qi_basename"
                done
            fi

            echo -e "${PURPLE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
            echo
        fi
    fi

    # Claude Code Progress section
    if [[ -f ".ralph/progress.json" ]]; then
        local progress_data=$(cat ".ralph/progress.json" 2>/dev/null)
        local progress_status=$(echo "$progress_data" | jq -r '.status // "idle"' 2>/dev/null || echo "idle")
        
        if [[ "$progress_status" == "executing" ]]; then
            local indicator=$(echo "$progress_data" | jq -r '.indicator // "⠋"' 2>/dev/null || echo "⠋")
            local elapsed=$(echo "$progress_data" | jq -r '.elapsed_seconds // "0"' 2>/dev/null || echo "0")
            local last_output=$(echo "$progress_data" | jq -r '.last_output // ""' 2>/dev/null || echo "")
            
            echo -e "${YELLOW}┌─ Claude Code Progress ──────────────────────────────────────────────────┐${NC}"
            echo -e "${YELLOW}│${NC} Status:         ${indicator} Working (${elapsed}s elapsed)"
            if [[ -n "$last_output" && "$last_output" != "" ]]; then
                # Truncate long output for display
                local display_output=$(echo "$last_output" | head -c 60)
                echo -e "${YELLOW}│${NC} Output:         ${display_output}..."
            fi
            echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────────────┘${NC}"
            echo
        fi
    fi
    
    # Recent logs
    echo -e "${BLUE}┌─ Recent Activity ───────────────────────────────────────────────────────┐${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 8 "$LOG_FILE" | while IFS= read -r line; do
            echo -e "${BLUE}│${NC} $line"
        done
    else
        echo -e "${BLUE}│${NC} No log file found"
    fi
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    
    # Footer
    echo
    echo -e "${YELLOW}Controls: Ctrl+C to exit | Refreshes every ${REFRESH_INTERVAL}s | $(date '+%H:%M:%S')${NC}"
}

# Main monitor loop
main() {
    echo "Starting Ralph Monitor..."
    sleep 2
    
    while true; do
        display_status
        sleep "$REFRESH_INTERVAL"
    done
}

main
