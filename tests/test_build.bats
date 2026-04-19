#!/usr/bin/env bats
# Tests for the build subcommand.

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

# Create a minimal Containerfile in the config dir.
make_containerfile() {
    local suffix="$1"
    local file="$HOME/.config/claude-sandbox/Containerfile.${suffix}"
    if [ "$suffix" = "base" ]; then
        echo "FROM ubuntu:24.04" > "$file"
    else
        echo "FROM claude-ubuntu" > "$file"
    fi
}

log_has() { grep -qF -- "$1" "$MOCK_PODMAN_LOG"; }

# ── build base image ──────────────────────────────────────────────────────────

@test "build with no args exits 1 when Containerfile.base is missing" {
    run "$SCRIPT" build
    [ "$status" -eq 1 ]
}

@test "build with no args prints error when Containerfile.base is missing" {
    run "$SCRIPT" build
    [[ "$output" == *"Containerfile not found"* ]]
}

@test "build with no args mentions init when Containerfile.base is missing" {
    run "$SCRIPT" build
    [[ "$output" == *"claude-sandbox init"* ]]
}

@test "build with no args calls podman build with claude-ubuntu tag" {
    make_containerfile base
    run "$SCRIPT" build
    [ "$status" -eq 0 ]
    log_has "-t claude-ubuntu"
}

@test "build with no args passes Containerfile.base to podman" {
    make_containerfile base
    run "$SCRIPT" build
    log_has "Containerfile.base"
}

@test "build with no args passes -f flag to podman build" {
    make_containerfile base
    run "$SCRIPT" build
    log_has "-f"
}

@test "build with no args prints the image tag being built" {
    make_containerfile base
    run "$SCRIPT" build
    [[ "$output" == *"claude-ubuntu"* ]]
}

@test "build with no args prints the Containerfile path" {
    make_containerfile base
    run "$SCRIPT" build
    [[ "$output" == *"Containerfile.base"* ]]
}

@test "build with no args prints success message" {
    make_containerfile base
    run "$SCRIPT" build
    [[ "$output" == *"Built: claude-ubuntu"* ]]
}

# ── build extended image ──────────────────────────────────────────────────────

@test "build <suffix> exits 1 when Containerfile.<suffix> is missing" {
    run "$SCRIPT" build postgres
    [ "$status" -eq 1 ]
}

@test "build <suffix> prints error when Containerfile.<suffix> is missing" {
    run "$SCRIPT" build postgres
    [[ "$output" == *"Containerfile not found"* ]]
}

@test "build <suffix> error mentions how to create the Containerfile" {
    run "$SCRIPT" build postgres
    [[ "$output" == *"FROM claude-ubuntu"* ]]
}

@test "build <suffix> calls podman build with claude-ubuntu-<suffix> tag" {
    make_containerfile postgres
    run "$SCRIPT" build postgres
    [ "$status" -eq 0 ]
    log_has "-t claude-ubuntu-postgres"
}

@test "build <suffix> passes Containerfile.<suffix> to podman" {
    make_containerfile postgres
    run "$SCRIPT" build postgres
    log_has "Containerfile.postgres"
}

@test "build <suffix> prints the image tag being built" {
    make_containerfile postgres
    run "$SCRIPT" build postgres
    [[ "$output" == *"claude-ubuntu-postgres"* ]]
}

@test "build <suffix> prints success message with tag" {
    make_containerfile postgres
    run "$SCRIPT" build postgres
    [[ "$output" == *"Built: claude-ubuntu-postgres"* ]]
}

# ── error propagation ─────────────────────────────────────────────────────────

@test "build exits non-zero when podman build fails" {
    make_containerfile base
    export MOCK_PODMAN_FAIL="build"
    run "$SCRIPT" build
    [ "$status" -ne 0 ]
}

# ── guard ─────────────────────────────────────────────────────────────────────

@test "build requires init" {
    rm -f "$HOME/.config/claude-sandbox/config"
    run "$SCRIPT" build
    [ "$status" -eq 1 ]
    [[ "$output" == *"not initialized"* ]]
}

# ── logging ───────────────────────────────────────────────────────────────────

@test "build logs INFO at start" {
    make_containerfile base
    "$SCRIPT" build >/dev/null
    grep -qF "[INFO ] cmd_build: rebuilding base image" "$LOG_FILE"
}

@test "build logs DEBUG for containerfile path" {
    make_containerfile base
    "$SCRIPT" build >/dev/null
    grep -qF "[DEBUG] cmd_build: containerfile=" "$LOG_FILE"
}

@test "build logs INFO on success" {
    make_containerfile base
    "$SCRIPT" build >/dev/null
    grep -qF "[INFO ] cmd_build: image 'claude-ubuntu' built successfully" "$LOG_FILE"
}

@test "build logs ERROR when Containerfile missing" {
    run "$SCRIPT" build
    grep -qF "[ERROR] cmd_build: Containerfile not found" "$LOG_FILE"
}

@test "build extended image logs INFO at start" {
    make_containerfile python
    "$SCRIPT" build python >/dev/null
    grep -qF "[INFO ] cmd_build: rebuilding extended image 'claude-ubuntu-python'" "$LOG_FILE"
}
