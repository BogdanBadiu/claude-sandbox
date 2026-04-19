#!/usr/bin/env bats
# Tests for the init subcommand.
# Package managers (dnf, apt-get, etc.) and sudo are mocked via mock_command.
# Podman is mocked via mock_podman. User prompts are handled via piped stdin.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"
MOCK_PODMAN_SRC="$BATS_TEST_DIRNAME/mock_podman"
MOCK_CMD_SRC="$BATS_TEST_DIRNAME/mock_command"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"

    export BASE
    BASE="$(mktemp -d)"

    # Mock bin: podman + sudo + package managers + curl + git
    export MOCK_BIN
    MOCK_BIN="$(mktemp -d)"

    # podman mock (state-aware)
    cp "$MOCK_PODMAN_SRC" "$MOCK_BIN/podman"
    chmod +x "$MOCK_BIN/podman"

    # generic mocks for package managers, sudo, curl, git
    for cmd in sudo dnf apt-get pacman zypper apk curl git; do
        cp "$MOCK_CMD_SRC" "$MOCK_BIN/$cmd"
        chmod +x "$MOCK_BIN/$cmd"
    done

    export PATH="$MOCK_BIN:$PATH"

    export MOCK_CMD_SRC

    export MOCK_PODMAN_LOG
    MOCK_PODMAN_LOG="$(mktemp)"
    export MOCK_COMMAND_LOG
    MOCK_COMMAND_LOG="$(mktemp)"

    # Default podman state: base image does NOT exist yet
    export MOCK_RUNNING="" MOCK_STOPPED="" MOCK_IMAGES="" MOCK_PODMAN_FAIL=""
    export MOCK_COMMAND_FAIL=""

    # Restrict _init_ensure_tool to MOCK_BIN so tests can simulate missing tools
    # by removing them from MOCK_BIN without system binaries leaking through.
    export _INIT_TOOL_PATH="$MOCK_BIN"

    # Override os-release and getenforce for all tests
    export OS_RELEASE_FILE="$HOME/os-release"
    export GETENFORCE_CMD="$MOCK_BIN/getenforce"

    # Default: ubuntu, selinux unknown
    echo 'ID=ubuntu' > "$OS_RELEASE_FILE"
    printf '#!/bin/sh\nexit 1\n' > "$MOCK_BIN/getenforce"
    chmod +x "$MOCK_BIN/getenforce"

    export LOG_FILE="$HOME/.local/share/claude-sandbox/claude-sandbox.log"
}

teardown() {
    rm -rf "$HOME" "$BASE" "$MOCK_BIN" "$MOCK_PODMAN_LOG" "$MOCK_COMMAND_LOG"
    export HOME="$REAL_HOME"
}

# Helpers
run_init() {
    # $1 = newline-separated stdin responses (one per prompt)
    local input="${1:-$BASE}"
    local stdin_file
    stdin_file=$(mktemp)
    printf '%s\n' "$input" > "$stdin_file"
    run "$SCRIPT" init < "$stdin_file"
    rm -f "$stdin_file"
}

cmd_log_has() { grep -qF -- "$1" "$MOCK_COMMAND_LOG"; }
podman_log_has() { grep -qF -- "$1" "$MOCK_PODMAN_LOG"; }

# ── Config file ───────────────────────────────────────────────────────────────

@test "init creates config file" {
    run_init "$BASE"
    [ -f "$HOME/.config/claude-sandbox/config" ]
}

@test "init writes CLAUDE_SANDBOX_BASE to config" {
    run_init "$BASE"
    grep -q "CLAUDE_SANDBOX_BASE=" "$HOME/.config/claude-sandbox/config"
}

@test "init writes the entered base dir to config" {
    run_init "$BASE"
    grep -q "\"$BASE\"" "$HOME/.config/claude-sandbox/config"
}

@test "init uses default base dir when user presses Enter" {
    local stdin_file; stdin_file=$(mktemp)
    printf '\n' > "$stdin_file"
    run "$SCRIPT" init < "$stdin_file"
    rm -f "$stdin_file"
    [ -f "$HOME/.config/claude-sandbox/config" ]
}

@test "init creates CLAUDE_SANDBOX_BASE directory if it does not exist" {
    local new_base="$HOME/new-sandbox-dir"
    run_init "$new_base"
    [ -d "$new_base" ]
}

@test "init does not error if CLAUDE_SANDBOX_BASE already exists" {
    run_init "$BASE"
    [ "$status" -eq 0 ]
}

# ── Containerfile.base ────────────────────────────────────────────────────────

@test "init creates Containerfile.base" {
    run_init "$BASE"
    [ -f "$HOME/.config/claude-sandbox/Containerfile.base" ]
}

@test "Containerfile.base starts with FROM ubuntu:24.04" {
    run_init "$BASE"
    head -1 "$HOME/.config/claude-sandbox/Containerfile.base" | grep -q "^FROM ubuntu:24.04$"
}

@test "Containerfile.base contains Claude Code installation" {
    run_init "$BASE"
    grep -q "claude.ai/install.sh" "$HOME/.config/claude-sandbox/Containerfile.base"
}

@test "Containerfile.base contains home volume mount workaround" {
    run_init "$BASE"
    grep -q "/usr/local/share/claude" "$HOME/.config/claude-sandbox/Containerfile.base"
}

@test "Containerfile.base contains user setup via ARG" {
    run_init "$BASE"
    grep -q "ARG USERNAME" "$HOME/.config/claude-sandbox/Containerfile.base"
    grep -q "usermod -l \${USERNAME}" "$HOME/.config/claude-sandbox/Containerfile.base"
}

@test "init does not overwrite existing Containerfile.base" {
    mkdir -p "$HOME/.config/claude-sandbox"
    echo "CUSTOM CONTENT" > "$HOME/.config/claude-sandbox/Containerfile.base"
    run_init "$BASE"
    grep -q "CUSTOM CONTENT" "$HOME/.config/claude-sandbox/Containerfile.base"
}

@test "init reports that existing Containerfile.base is kept" {
    mkdir -p "$HOME/.config/claude-sandbox"
    echo "FROM custom" > "$HOME/.config/claude-sandbox/Containerfile.base"
    run_init "$BASE"
    [[ "$output" == *"already exists"* ]]
}

# ── Podman build ──────────────────────────────────────────────────────────────

@test "init runs podman build when image does not exist" {
    run_init "$BASE"
    podman_log_has "build --build-arg"
    podman_log_has "-t claude-ubuntu"
}

@test "init skips podman build when image already exists" {
    export MOCK_IMAGES="claude-ubuntu"
    run_init "$BASE"
    ! podman_log_has "build -t claude-ubuntu"
}

@test "init prints skip message when image already exists" {
    export MOCK_IMAGES="claude-ubuntu"
    run_init "$BASE"
    [[ "$output" == *"already exists"* ]]
}

# ── Tool installation ─────────────────────────────────────────────────────────

@test "init installs podman when missing on ubuntu" {
    rm "$MOCK_BIN/podman"   # remove podman from mock PATH
    run_init "$BASE"
    cmd_log_has "apt-get install"
    cmd_log_has "podman"
}

@test "init installs podman when missing on fedora" {
    echo 'ID=fedora' > "$OS_RELEASE_FILE"
    rm "$MOCK_BIN/podman"
    # mock_command auto-creates $MOCK_BIN/podman when dnf install podman runs
    run_init "$BASE"
    cmd_log_has "dnf install"
}

@test "init exits with error when podman missing on unknown distro" {
    echo 'ID=gentoo' > "$OS_RELEASE_FILE"
    rm "$MOCK_BIN/podman"
    run_init "$BASE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not installed"* ]]
}

@test "init installs curl when missing" {
    rm "$MOCK_BIN/curl"
    run_init "$BASE"
    cmd_log_has "apt-get install"
    cmd_log_has "curl"
}


# ── Distro detection in init ──────────────────────────────────────────────────

@test "init shows detected distribution" {
    run_init "$BASE"
    [[ "$output" == *"ubuntu"* ]]
}

@test "init shows package manager" {
    run_init "$BASE"
    [[ "$output" == *"apt-get"* ]]
}

@test "init shows SELinux state" {
    run_init "$BASE"
    [[ "$output" == *"SELinux"* ]]
}

@test "init prints SELinux enforcing note on enforcing system" {
    printf '#!/bin/sh\necho Enforcing\n' > "$MOCK_BIN/getenforce"
    run_init "$BASE"
    [[ "$output" == *"enforcing"* ]]
}

# ── Re-initialisation ─────────────────────────────────────────────────────────

@test "init keeps existing base dir when user accepts" {
    run_init "$BASE"
    local stdin_file; stdin_file=$(mktemp)
    printf 'Y\n' > "$stdin_file"
    run "$SCRIPT" init < "$stdin_file"
    rm -f "$stdin_file"
    [ "$status" -eq 0 ]
    grep -q "\"$BASE\"" "$HOME/.config/claude-sandbox/config"
}

@test "init updates base dir when user declines keep" {
    run_init "$BASE"
    local new_base="$HOME/new-base"
    local stdin_file; stdin_file=$(mktemp)
    printf 'n\n%s\n' "$new_base" > "$stdin_file"
    run "$SCRIPT" init < "$stdin_file"
    rm -f "$stdin_file"
    [ "$status" -eq 0 ]
    grep -q "\"$new_base\"" "$HOME/.config/claude-sandbox/config"
}

# ── Shell completion ──────────────────────────────────────────────────────────

@test "init installs bash completion file" {
    run_init "$BASE"
    [ -f "$HOME/.local/share/bash-completion/completions/claude-sandbox" ]
}

@test "bash completion file contains complete -F line" {
    run_init "$BASE"
    grep -q "complete -F _claude_sandbox" \
        "$HOME/.local/share/bash-completion/completions/claude-sandbox"
}

@test "init creates bashrc.d source file" {
    run_init "$BASE"
    [ -f "$HOME/.bashrc.d/claude-sandbox" ]
}

@test "bashrc.d file sources the completion" {
    run_init "$BASE"
    grep -q "source" "$HOME/.bashrc.d/claude-sandbox"
}

@test "init installs zsh completion when SHELL is zsh" {
    SHELL=/bin/zsh run_init "$BASE"
    [ -f "$HOME/.zfunc/_claude-sandbox" ]
}

@test "zsh completion file contains compdef line" {
    SHELL=/bin/zsh run_init "$BASE"
    grep -q "#compdef claude-sandbox" "$HOME/.zfunc/_claude-sandbox"
}

# ── Summary ───────────────────────────────────────────────────────────────────

@test "init prints ready message" {
    run_init "$BASE"
    [[ "$output" == *"claude-sandbox is ready"* ]]
}

@test "init prints next-steps hint" {
    run_init "$BASE"
    [[ "$output" == *"claude-sandbox new"* ]]
}

@test "init exits 0 on success" {
    run_init "$BASE"
    [ "$status" -eq 0 ]
}

# ── Logging ───────────────────────────────────────────────────────────────────

@test "init logs start at INFO level" {
    run_init "$BASE"
    grep -qF "[INFO ] cmd_init: starting initialization" "$LOG_FILE"
}

@test "init logs completion at INFO level" {
    run_init "$BASE"
    grep -qF "[INFO ] cmd_init: initialization complete" "$LOG_FILE"
}

@test "init logs CLAUDE_SANDBOX_BASE at INFO level" {
    run_init "$BASE"
    grep -qF "[INFO ] cmd_init: CLAUDE_SANDBOX_BASE=" "$LOG_FILE"
}

@test "init logs error when podman missing on unknown distro" {
    echo 'ID=gentoo' > "$OS_RELEASE_FILE"
    rm "$MOCK_BIN/podman"
    run_init "$BASE"
    grep -qF "[ERROR]" "$LOG_FILE"
}
