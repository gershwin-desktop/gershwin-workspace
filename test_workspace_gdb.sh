#!/bin/bash

# Script to run Workspace in gdb with 10-second timeout
# Repeats until crash is detected or max iterations reached

WORKSPACE_BIN="./Workspace/Workspace.app/Workspace"
MAX_ITERATIONS=100
TIMEOUT=10
OUTPUT_DIR="./gdb_outputs"
ITERATION=1

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Starting Workspace crash detection loop..."
echo "Max iterations: $MAX_ITERATIONS"
echo "Timeout per run: ${TIMEOUT}s"
echo "================================"

while [ $ITERATION -le $MAX_ITERATIONS ]; do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_FILE="$OUTPUT_DIR/run_${ITERATION}_${TIMESTAMP}.log"
    
    echo ""
    echo "Iteration $ITERATION/$MAX_ITERATIONS - $(date)"
    
    # Create gdb command file
    cat > /tmp/gdb_commands.txt <<EOF
set pagination off
set non-stop off
set print thread-events off
run
bt full
thread apply all bt
quit
EOF
    
    # Run gdb with timeout
    timeout --signal=KILL ${TIMEOUT}s gdb -batch -x /tmp/gdb_commands.txt "$WORKSPACE_BIN" > "$OUTPUT_FILE" 2>&1
    EXIT_CODE=$?
    
    # Check for crash (segfault, abort, etc)
    if grep -qE "(Program received signal|Program terminated|Segmentation fault|SIGABRT|SIGSEGV|SIGBUS|Fatal|Assertion.*failed)" "$OUTPUT_FILE"; then
        echo "*** CRASH DETECTED! ***"
        echo "Output saved to: $OUTPUT_FILE"
        echo ""
        echo "=== CRASH SUMMARY ==="
        grep -A 20 "Program received signal\|Program terminated\|Fatal\|Assertion.*failed" "$OUTPUT_FILE" | head -30
        echo ""
        echo "=== BACKTRACE ==="
        grep -A 30 "^#0\|^#1\|^#2\|^#3\|^#4\|^#5" "$OUTPUT_FILE" | head -40
        exit 1
    fi
    
    # Check if process exited abnormally (not by timeout)
    if [ $EXIT_CODE -ne 124 ] && [ $EXIT_CODE -ne 137 ]; then
        echo "Process exited with code: $EXIT_CODE"
        if [ $EXIT_CODE -ne 0 ]; then
            echo "*** ABNORMAL EXIT DETECTED! ***"
            echo "Output saved to: $OUTPUT_FILE"
            tail -50 "$OUTPUT_FILE"
            exit 1
        fi
    else
        echo "Process killed by timeout (expected)"
    fi
    
    # Clean up old output if no crash
    rm -f "$OUTPUT_FILE"
    
    ITERATION=$((ITERATION + 1))
    sleep 0.5
done

echo ""
echo "Completed $MAX_ITERATIONS iterations without detecting a crash."
echo "You may want to increase MAX_ITERATIONS or TIMEOUT if crashes are intermittent."
