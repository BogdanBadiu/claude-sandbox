#!/usr/bin/env bats
# Tests for logging infrastructure and the logs subcommand.
bats_require_minimum_version 1.5.0

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"
MOCK_SRC="$BATS_TEST_DIRNAME/mock_podman"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"
    export BASE
    BASE="$(mktemp -d)"
    mkdir -p "$HOME/.config/claude-sandbox"
    echo "CLAUDE_SANDBOX_BASE=$BASE" > "$HOME/.config/claude-sandbox/config"

    export MOCK_BIN
    MOCK_BIN="$(mktemp -d)"
    cp "$MOCK_SRC" "$MOCK_BIN/podman"
    chmod +x "$MOCK_BIN/podman"
    export PATH="$MOCK_BIN:$PATH"

    export MOCK_PODMAN_LOG
    MOCK_PODMAN_LOG="$(mktemp)"
    export MOCK_RUNNING="" MOCK_STOPPED="" MOCK_IMAGES="claude-ubuntu" MOCK_PODMAN_FAIL=""

    export LOG_FILE="$HOME/.local/share/claude-sandbox/claude-sandbox.log"
}

teardown() {
    rm -rf "$HOME" "$BASE" "$MOCK_PODMAN_LOG" "$MOCK_BIN"
    export HOME="$REAL_HOME"
}

make_project() {
    local project="$1"
    mkdir -p "$BASE/$project/dev" "$BASE/$project/container"
    cat > "$BASE/$project/sandbox.conf" <<EOF
# Claude sandbox configuration for project: $project
# IMAGE_SUFFIX=
# EXTRA_PORTS=
SKIP_PERMISSIONS=true
EOF
}

# ── Log file creation ─────────────────────────────────────────────────────────

@test "log file is created when a subcommand runs" {
    make_project alpha
    run "$SCRIPT" new beta 2>/dev/null || true
    # new writes to the log; file should exist now
    "$SCRIPT" new gamma >/dev/null
    [ -f "$LOG_FILE" ]
}

@test "log file parent directory is created automatically" {
    make_project alpha
    [ ! -d "$HOME/.local/share/claude-sandbox" ]
    "$SCRIPT" new delta >/dev/null
    [ -d "$HOME/.local/share/claude-sandbox" ]
}

@test "logs subcommand reports missing log file cleanly" {
    run "$SCRIPT" logs
    [ "$status" -eq 0 ]
    [[ "$output" == *"No log file"* ]]
}

# ── Log levels written to file ────────────────────────────────────────────────

@test "INFO messages are written to the log file" {
    "$SCRIPT" new my-app >/dev/null
    grep -qF "[INFO ]" "$LOG_FILE"
}

@test "DEBUG messages are written to the log file" {
    "$SCRIPT" new my-app >/dev/null
    grep -qF "[DEBUG]" "$LOG_FILE"
}

@test "ERROR messages are written to the log file" {
    run "$SCRIPT" new my-app  # first create
    run "$SCRIPT" new my-app  # second create triggers error
    grep -qF "[ERROR]" "$LOG_FILE"
}

@test "log entries include a timestamp" {
    "$SCRIPT" new my-app >/dev/null
    # timestamp format: 2026-04-15T10:30:00
    grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$LOG_FILE"
}

# ── INFO and DEBUG not printed to terminal by default ────────────────────────

@test "INFO messages do not appear on stdout by default" {
    run "$SCRIPT" new my-app
    [[ "$output" != *"[INFO ]"* ]]
}

@test "DEBUG messages do not appear on stderr by default" {
    run --separate-stderr "$SCRIPT" new my-app
    [[ "$stderr" != *"[DEBUG]"* ]]
}

# ── --debug flag ──────────────────────────────────────────────────────────────

@test "--debug prints DEBUG messages to stderr" {
    run --separate-stderr "$SCRIPT" --debug new my-app
    [[ "$stderr" == *"[DEBUG]"* ]]
}

@test "--debug does not duplicate INFO messages to stderr" {
    run --separate-stderr "$SCRIPT" --debug new my-app
    [[ "$stderr" != *"[INFO ]"* ]]
}

@test "--debug still writes all levels to the log file" {
    "$SCRIPT" --debug new my-app >/dev/null 2>/dev/null
    grep -qF "[INFO ]" "$LOG_FILE"
    grep -qF "[DEBUG]" "$LOG_FILE"
}

@test "--debug works with logs subcommand without error" {
    "$SCRIPT" new my-app >/dev/null
    run "$SCRIPT" --debug logs
    [ "$status" -eq 0 ]
}

# ── Logging in cmd_new ────────────────────────────────────────────────────────

@test "cmd_new logs the project name at INFO level" {
    "$SCRIPT" new my-app >/dev/null
    grep -qF "[INFO ] cmd_new: creating project 'my-app'" "$LOG_FILE"
}

@test "cmd_new logs image suffix at DEBUG level" {
    "$SCRIPT" new my-app postgres >/dev/null
    grep -qF "[DEBUG] cmd_new: image_suffix='postgres'" "$LOG_FILE"
}

@test "cmd_new logs project dir at DEBUG level" {
    "$SCRIPT" new my-app >/dev/null
    grep -qF "[DEBUG] cmd_new: project dir will be" "$LOG_FILE"
}

@test "cmd_new logs success at INFO level" {
    "$SCRIPT" new my-app >/dev/null
    grep -qF "[INFO ] cmd_new: project 'my-app' created successfully" "$LOG_FILE"
}

@test "cmd_new logs error when project already exists" {
    "$SCRIPT" new my-app >/dev/null
    run "$SCRIPT" new my-app
    grep -qF "[ERROR] cmd_new: project 'my-app' already exists" "$LOG_FILE"
}

# ── Logging in cmd_start ──────────────────────────────────────────────────────

@test "cmd_start logs project name at INFO level" {
    make_project my-app
    "$SCRIPT" start my-app >/dev/null
    grep -qF "[INFO ] cmd_start: starting project 'my-app'" "$LOG_FILE"
}

@test "cmd_start logs selected image at DEBUG level" {
    make_project my-app
    "$SCRIPT" start my-app >/dev/null
    grep -qF "[DEBUG] cmd_start:" "$LOG_FILE"
    grep -qF "claude-ubuntu" "$LOG_FILE"
}

@test "cmd_start logs container state at DEBUG level" {
    make_project my-app
    "$SCRIPT" start my-app >/dev/null
    grep -qF "[DEBUG] cmd_start: container" "$LOG_FILE"
}

@test "cmd_start logs error when project not found" {
    run "$SCRIPT" start ghost
    grep -qF "[ERROR] cmd_start: project 'ghost' not found" "$LOG_FILE"
}

@test "cmd_start logs error when image not found" {
    make_project db-app
    echo "IMAGE_SUFFIX=missing" >> "$BASE/db-app/sandbox.conf"
    run "$SCRIPT" start db-app
    grep -qF "[ERROR] cmd_start: image 'claude-ubuntu-missing' not found" "$LOG_FILE"
}

# ── Logging in cmd_stop ───────────────────────────────────────────────────────

@test "cmd_stop logs project name at INFO level" {
    make_project my-app
    export MOCK_RUNNING="claude-my-app"
    "$SCRIPT" stop my-app >/dev/null
    grep -qF "[INFO ] cmd_stop: stopping project 'my-app'" "$LOG_FILE"
}

@test "cmd_stop logs error when project not found" {
    run "$SCRIPT" stop ghost
    grep -qF "[ERROR] cmd_stop: project 'ghost' not found" "$LOG_FILE"
}

# ── logs subcommand ───────────────────────────────────────────────────────────

@test "logs subcommand exits 0" {
    "$SCRIPT" new my-app >/dev/null
    run "$SCRIPT" logs
    [ "$status" -eq 0 ]
}

@test "logs subcommand shows log content" {
    "$SCRIPT" new my-app >/dev/null
    run "$SCRIPT" logs
    [[ "$output" == *"cmd_new"* ]]
}

@test "logs --lines limits output" {
    # generate more than 3 log lines
    for i in 1 2 3 4 5; do
        "$SCRIPT" new "proj-${i}" >/dev/null
    done
    local total
    total=$(wc -l < "$LOG_FILE")
    run "$SCRIPT" logs --lines 3
    [ "$status" -eq 0 ]
    # output should have at most 3 lines
    local out_lines
    out_lines=$(echo "$output" | wc -l)
    [ "$out_lines" -le 3 ]
    # and total log is more than 3
    [ "$total" -gt 3 ]
}

@test "logs --lines requires an argument" {
    "$SCRIPT" new my-app >/dev/null
    run "$SCRIPT" logs --lines
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a positive integer"* ]]
}

@test "logs --lines rejects non-numeric argument" {
    "$SCRIPT" new my-app >/dev/null
    run "$SCRIPT" logs --lines abc
    [ "$status" -eq 1 ]
}

@test "logs rejects unknown flags" {
    run "$SCRIPT" logs --verbose
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown argument"* ]]
}

@test "logs does not require init" {
    # wipe config entirely
    rm -f "$HOME/.config/claude-sandbox/config"
    run "$SCRIPT" logs
    [ "$status" -eq 0 ]
    [[ "$output" != *"not initialized"* ]]
}

@test "logs is listed in help output" {
    run "$SCRIPT" help
    [[ "$output" == *"logs"* ]]
}
