#!/usr/bin/env bats
# Tests for config file loading and the uninitialized guard.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"

setup() {
    # Each test gets a fresh temp HOME so config state is isolated
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"
}

teardown() {
    rm -rf "$HOME"
    export HOME="$REAL_HOME"
}

# ── Config absent ─────────────────────────────────────────────────────────────

@test "status works when config is absent" {
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "guarded subcommand exits 1 when config is absent" {
    run "$SCRIPT" list
    [ "$status" -eq 1 ]
    [[ "$output" == *"not initialized"* ]]
}

@test "guarded subcommand error mentions init" {
    run "$SCRIPT" list
    [[ "$output" == *"claude-sandbox init"* ]]
}

@test "init subcommand is not blocked by missing config" {
    # init must not call require_init — it should run (not print the guard error)
    local stdin_file
    stdin_file=$(mktemp)
    local base
    base=$(mktemp -d)
    printf '%s\n' "$base" > "$stdin_file"
    run "$SCRIPT" init < "$stdin_file"
    rm -f "$stdin_file"
    rm -rf "$base"
    [[ "$output" != *"not initialized"* ]]
}

@test "help subcommand is not blocked by missing config" {
    run "$SCRIPT" help
    [ "$status" -eq 0 ]
}

# ── Config present ────────────────────────────────────────────────────────────

setup_config() {
    mkdir -p "$HOME/.config/claude-sandbox"
    cat > "$HOME/.config/claude-sandbox/config" <<EOF
# claude-sandbox configuration
CLAUDE_SANDBOX_BASE="$HOME/projects"
EOF
}

@test "status shows base dir from config" {
    setup_config
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"$HOME/projects"* ]]
}

@test "status reports directory not found when base dir missing" {
    setup_config
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"directory not found"* ]]
}

@test "status reports exists when base dir present" {
    setup_config
    mkdir -p "$HOME/projects"
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"(exists)"* ]]
}

@test "config ignores comment lines" {
    mkdir -p "$HOME/.config/claude-sandbox"
    cat > "$HOME/.config/claude-sandbox/config" <<EOF
# CLAUDE_SANDBOX_BASE=/should/not/be/read
CLAUDE_SANDBOX_BASE=/real/path
EOF
    run "$SCRIPT" status
    [[ "$output" != *"/should/not/be/read"* ]]
    [[ "$output" == *"/real/path"* ]]
}

@test "config ignores blank lines" {
    mkdir -p "$HOME/.config/claude-sandbox"
    printf '\n\nCLAUDE_SANDBOX_BASE=/blank/test\n\n' \
        > "$HOME/.config/claude-sandbox/config"
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"/blank/test"* ]]
}

@test "guarded subcommand passes guard when config present" {
    setup_config
    mkdir -p "$HOME/projects"
    # list is implemented and base dir exists — should succeed, not hit the guard
    run "$SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" != *"not initialized"* ]]
}

# ── Unknown subcommand ────────────────────────────────────────────────────────

@test "unknown subcommand exits 1 with helpful message" {
    run "$SCRIPT" bogus-cmd
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown subcommand"* ]]
    [[ "$output" == *"claude-sandbox help"* ]]
}
