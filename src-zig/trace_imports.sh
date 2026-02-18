#!/bin/bash

# Start with the entry point
TO_PROCESS=("cursed_compiler_main.zig")
PROCESSED=()
REACHABLE=("cursed_compiler_main.zig")

# Process queue
while [ ${#TO_PROCESS[@]} -gt 0 ]; do
    # Get first item
    FILE="${TO_PROCESS[0]}"
    TO_PROCESS=("${TO_PROCESS[@]:1}")
    
    # Skip if already processed
    if [[ " ${PROCESSED[@]} " =~ " ${FILE} " ]]; then
        continue
    fi
    
    PROCESSED+=("$FILE")
    
    # Extract imports from the file
    if [ -f "$FILE" ]; then
        while IFS= read -r line; do
            if [[ $line =~ @import\(\"([^\"]+)\.zig\"\) ]]; then
                IMPORT="${BASH_REMATCH[1]}.zig"
                # Skip std and builtin
                if [[ "$IMPORT" != "std" && "$IMPORT" != "builtin" ]]; then
                    # Check if file exists
                    if [ -f "$IMPORT" ]; then
                        # Add to reachable if not already there
                        if [[ ! " ${REACHABLE[@]} " =~ " ${IMPORT} " ]]; then
                            REACHABLE+=("$IMPORT")
                        fi
                        # Add to processing queue if not processed
                        if [[ ! " ${PROCESSED[@]} " =~ " ${IMPORT} " ]]; then
                            TO_PROCESS+=("$IMPORT")
                        fi
                    fi
                fi
            fi
        done < "$FILE"
    fi
done

# Sort and output
printf '%s\n' "${REACHABLE[@]}" | sort
