#!/usr/bin/env bats
# Tests for the claude-md subcommand.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"

    export BASE
    BASE="$(mktemp -d)"

    mkdir -p "$HOME/.config/claude-sandbox"
    echo "CLAUDE_SANDBOX_BASE=\"$BASE\"" > "$HOME/.config/claude-sandbox/config"
}

teardown() {
    rm -rf "$HOME" "$BASE"
    export HOME="$REAL_HOME"
}

make_project() {
    local project="$1"
    mkdir -p "$BASE/$project/dev" "$BASE/$project/container"
    cat > "$BASE/$project/sandbox.conf" <<EOF
SKIP_PERMISSIONS=true
EOF
}

# ── Argument validation ───────────────────────────────────────────────────────

@test "claude-md requires a project name" {
    run "$SCRIPT" claude-md
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "claude-md fails for non-existent project" {
    run "$SCRIPT" claude-md ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "claude-md error mentions new command" {
    run "$SCRIPT" claude-md ghost
    [[ "$output" == *"claude-sandbox new ghost"* ]]
}

# ── Copy mode (with path) ─────────────────────────────────────────────────────

@test "claude-md with path copies file to project dev dir" {
    make_project my-app
    local src; src="$(mktemp)"
    echo "# My instructions" > "$src"
    run "$SCRIPT" claude-md my-app "$src"
    [ "$status" -eq 0 ]
    [ -f "$BASE/my-app/dev/CLAUDE.md" ]
    rm -f "$src"
}

@test "claude-md with path copies correct content" {
    make_project my-app
    local src; src="$(mktemp)"
    echo "# My instructions" > "$src"
    "$SCRIPT" claude-md my-app "$src"
    grep -q "My instructions" "$BASE/my-app/dev/CLAUDE.md"
    rm -f "$src"
}

@test "claude-md with path prints confirmation" {
    make_project my-app
    local src; src="$(mktemp)"
    echo "# test" > "$src"
    run "$SCRIPT" claude-md my-app "$src"
    [[ "$output" == *"Set:"* ]]
    rm -f "$src"
}

@test "claude-md with path fails when file does not exist" {
    make_project my-app
    run "$SCRIPT" claude-md my-app /nonexistent/CLAUDE.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "claude-md with path asks before overwriting existing CLAUDE.md" {
    make_project my-app
    echo "# existing" > "$BASE/my-app/dev/CLAUDE.md"
    local src; src="$(mktemp)"
    echo "# new" > "$src"
    local stdin_file; stdin_file="$(mktemp)"
    printf 'n\n' > "$stdin_file"
    run "$SCRIPT" claude-md my-app "$src" < "$stdin_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
    rm -f "$src" "$stdin_file"
}

@test "claude-md with path overwrites when user confirms" {
    make_project my-app
    echo "# existing" > "$BASE/my-app/dev/CLAUDE.md"
    local src; src="$(mktemp)"
    echo "# new content" > "$src"
    local stdin_file; stdin_file="$(mktemp)"
    printf 'y\n' > "$stdin_file"
    "$SCRIPT" claude-md my-app "$src" < "$stdin_file"
    grep -q "new content" "$BASE/my-app/dev/CLAUDE.md"
    rm -f "$src" "$stdin_file"
}

# ── Edit mode (no path) ───────────────────────────────────────────────────────

@test "claude-md with no path creates template when CLAUDE.md absent" {
    make_project my-app
    EDITOR="true" run "$SCRIPT" claude-md my-app
    [ -f "$BASE/my-app/dev/CLAUDE.md" ]
}

@test "claude-md template contains project name" {
    make_project my-app
    EDITOR="true" "$SCRIPT" claude-md my-app
    grep -q "my-app" "$BASE/my-app/dev/CLAUDE.md"
}

@test "claude-md with no path opens editor" {
    make_project my-app
    local editor_log; editor_log="$(mktemp)"
    local fake_editor; fake_editor="$(mktemp)"
    chmod +x "$fake_editor"
    printf '#!/bin/sh\necho "opened: $1" >> "%s"\n' "$editor_log" > "$fake_editor"
    EDITOR="$fake_editor" run "$SCRIPT" claude-md my-app
    grep -q "opened:.*CLAUDE.md" "$editor_log"
    rm -f "$editor_log" "$fake_editor"
}

@test "claude-md with no path does not overwrite existing CLAUDE.md before opening editor" {
    make_project my-app
    echo "# keep me" > "$BASE/my-app/dev/CLAUDE.md"
    EDITOR="true" "$SCRIPT" claude-md my-app
    grep -q "keep me" "$BASE/my-app/dev/CLAUDE.md"
}

# ── Logging ───────────────────────────────────────────────────────────────────

@test "claude-md logs info on copy" {
    make_project my-app
    local src; src="$(mktemp)"
    echo "# test" > "$src"
    run "$SCRIPT" claude-md my-app "$src"
    grep -q "cmd_claude_md" "$HOME/.local/share/claude-sandbox/claude-sandbox.log"
    rm -f "$src"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "claude-md is listed in help output" {
    run "$SCRIPT" help
    [[ "$output" == *"claude-md"* ]]
}
