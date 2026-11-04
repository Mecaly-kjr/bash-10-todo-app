#!/usr/bin/env bash

set -o pipefail

DATA_FILE="${TODO_FILE:-$HOME/.local/share/todo/todo.txt}"

# Display usage information
usage() {
    cat <<'EOF'
Usage: ./todo.sh [COMMAND]

Commands:
  add [-p low|medium|high] TITLE  Add a new task
  list                           List all tasks
  done ID                        Mark a task as done
  delete ID                      Delete a task
  help                           Show this help message

Run ./todo.sh without arguments to list tasks.
EOF
}

# Display an error and exit
die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# Create storage directory and file
init_storage() {
    local directory
    directory=$(dirname "$DATA_FILE")

    mkdir -p "$directory" || die "Cannot create storage directory"

    if [[ ! -e "$DATA_FILE" ]]; then
        touch "$DATA_FILE" || die "Cannot create data file"
    fi

    [[ -f "$DATA_FILE" && -r "$DATA_FILE" && -w "$DATA_FILE" ]] ||
        die "Data file must be a readable and writable regular file"
}

# Add a new task
cmd_add() {
    local priority="medium"
    local opt
    local title
    local max_id=0
    local id

    local OPTIND=1

    while getopts ":p:" opt; do
        case "$opt" in
            p)
                priority="$OPTARG"
                ;;
            *)
                die "Usage: add [-p low|medium|high] TITLE"
                ;;
        esac
    done

    shift $((OPTIND - 1))

    title="$*"

    [[ -n "$title" ]] || die "Missing task title"

    [[ "$title" != *"|"* ]] || die "Task title cannot contain |"

    case "$priority" in
        low|medium|high)
            ;;
        *)
            die "Invalid priority: $priority. Use low, medium or high"
            ;;
    esac

    while IFS='|' read -r existing_id _; do
        if [[ "$existing_id" =~ ^[0-9]+$ ]] &&
            (( existing_id > max_id )); then
            max_id=$existing_id
        fi
    done < "$DATA_FILE"

    id=$((max_id + 1))

    printf '%s|todo|%s|%s\n' "$id" "$priority" "$title" >> "$DATA_FILE" ||
        die "Cannot save task"

    printf 'Added task %s\n' "$id"
}

# List all tasks
cmd_list() {
    if [[ ! -s "$DATA_FILE" ]]; then
        printf 'No tasks yet. Add one with: ./todo.sh add "Your task"\n'
        return 0
    fi

    printf '%-4s %-8s %-10s %s\n' "ID" "STATUS" "PRIORITY" "TITLE"

    awk -F'|' -v OFS='|' '
        NF >= 4 {
            p = ($3 == "high") ? 1 : ($3 == "medium") ? 2 : 3
            print p, $0
        }
    ' "$DATA_FILE" |
        sort -t'|' -k1,1n -k2,2n |
        cut -d'|' -f2- |
        while IFS='|' read -r id status priority title; do
            printf '%-4s %-8s %-10s %s\n' "$id" "$status" "$priority" "$title"
        done
}

# Mark a task as done
cmd_done() {
    local id="$1"
    local temp_file

    [[ "$id" =~ ^[1-9][0-9]*$ ]] || die "Please provide a valid task ID"

    temp_file=$(mktemp "${DATA_FILE}.tmp.XXXXXX") ||
        die "Cannot create temporary file"

    if ! awk -F'|' -v OFS='|' -v target="$id" '
        $1 == target {
            found = 1
            $2 = "done"
        }
        { print }
        END {
            if (!found) exit 1
        }
    ' "$DATA_FILE" > "$temp_file"; then
        rm -f "$temp_file"
        die "Task $id not found"
    fi

    if ! mv "$temp_file" "$DATA_FILE"; then
        rm -f "$temp_file"
        die "Cannot update task"
    fi

    printf 'Task %s done\n' "$id"
}

# Delete a task
cmd_delete() {
    local id="$1"
    local temp_file

    [[ "$id" =~ ^[1-9][0-9]*$ ]] || die "Please provide a valid task ID"

    temp_file=$(mktemp "${DATA_FILE}.tmp.XXXXXX") ||
        die "Cannot create temporary file"

    if ! awk -F'|' -v target="$id" '
        $1 == target {
            found = 1
            next
        }
        { print }
        END {
            if (!found) exit 1
        }
    ' "$DATA_FILE" > "$temp_file"; then
        rm -f "$temp_file"
        die "Task $id not found"
    fi

    if ! mv "$temp_file" "$DATA_FILE"; then
        rm -f "$temp_file"
        die "Cannot delete task"
    fi

    printf 'Task %s deleted\n' "$id"
}

# Main function
main() {
    local command="${1:-list}"

    if [[ "$command" == "help" ]]; then
        usage
        exit 0
    fi

    init_storage

    case "$command" in
        add)
            shift
            cmd_add "$@"
            ;;
        list)
            [[ $# -eq 1 ]] || die "Usage: ./todo.sh list"
            cmd_list
            ;;
        done)
            [[ $# -eq 2 ]] || die "Usage: ./todo.sh done ID"
            shift
            cmd_done "$1"
            ;;
        delete)
            [[ $# -eq 2 ]] || die "Usage: ./todo.sh delete ID"
            shift
            cmd_delete "$1"
            ;;
        *)
            die "Unknown command: $command. Run ./todo.sh help"
            ;;
    esac
}

main "$@"
