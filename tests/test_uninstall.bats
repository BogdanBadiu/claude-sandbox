#!/usr/bin/env bats
# Tests for the uninstall subcommand.
# Podman is mocked; no real containers or images are touched.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"
MOCK_SRC="$BATS_TEST_DIRNAME/mock_podman"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"

    export BASE
    BASE="$(mktemp -d)"

    export MOCK_BIN
    MOCK_BIN="$(mktemp -d)"
    cp "$MOCK_SRC" "$MOCK_BIN/podman"
    chmod +x "$MOCK_BIN/podman"
    export PATH="$MOCK_BIN:$PATH"

    export MOCK_PODMAN_LOG
    MOCK_PODMAN_LOG="$(mktemp)"

    export MOCK_RUNNING=""
    export MOCK_STOPPED=""
    export MOCK_IMAGES="claude-ubuntu"
    export MOCK_PODMAN_FAIL=""

    # Write config so the tool knows the base dir
    mkdir -p "$HOME/.config/claude-sandbox"
    echo "CLAUDE_SANDBOX_BASE=\"$BASE\"" > "$HOME/.config/claude-sandbox/config"

    # Fake binary location
    mkdir -p "$HOME/.local/bin"
    cp "$SCRIPT" "$HOME/.local/bin/claude-sandbox"
    chmod +x "$HOME/.local/bin/claude-sandbox"
    export PATH="$HOME/.local/bin:$PATH"
}

teardown() {
    rm -rf "$HOME" "$BASE" "$MOCK_BIN" "$MOCK_PODMAN_LOG"
    export HOME="$REAL_HOME"
}

# Helper: run uninstall with a single "yes" confirmation
run_uninstall() {
    local stdin_file; stdin_file="$(mktemp)"
    printf 'yes\n' > "$stdin_file"
    run "$SCRIPT" uninstall "$@" < "$stdin_file"
    rm -f "$stdin_file"
}

run_uninstall_cancel() {
    local stdin_file; stdin_file="$(mktemp)"
    printf 'no\n' > "$stdin_file"
    run "$SCRIPT" uninstall < "$stdin_file"
    rm -f "$stdin_file"
}

podman_log_has() { grep -qF -- "$1" "$MOCK_PODMAN_LOG"; }

# ── Confirmation prompt ───────────────────────────────────────────────────────

@test "uninstall exits 0 when confirmed" {
    run_uninstall
    [ "$status" -eq 0 ]
}

@test "uninstall cancels when user does not type yes" {
    run_uninstall_cancel
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
}

@test "uninstall shows what will be removed" {
    run_uninstall
    [[ "$output" == *"containers"* ]]
    [[ "$output" == *"Config:"* ]]
    [[ "$output" == *"Logs:"* ]]
}

# ── Container and image removal ───────────────────────────────────────────────

@test "uninstall calls podman ps to list containers" {
    run_uninstall
    podman_log_has "ps -a"
}

@test "uninstall removes running containers" {
    export MOCK_RUNNING="claude-my-app"
    run_uninstall
    podman_log_has "rm -f claude-my-app"
}

@test "uninstall removes stopped containers" {
    export MOCK_STOPPED="claude-old-app"
    run_uninstall
    podman_log_has "rm -f claude-old-app"
}

@test "uninstall calls podman images to list images" {
    run_uninstall
    podman_log_has "images"
}

@test "uninstall removes claude-ubuntu image" {
    run_uninstall
    podman_log_has "rmi -f claude-ubuntu"
}

@test "uninstall removes extended images" {
    export MOCK_IMAGES="claude-ubuntu claude-ubuntu-postgres"
    run_uninstall
    # both images passed together in one rmi call
    podman_log_has "claude-ubuntu-postgres"
}

# ── Config and log removal ────────────────────────────────────────────────────

@test "uninstall removes config directory" {
    run_uninstall
    [ ! -d "$HOME/.config/claude-sandbox" ]
}

@test "uninstall removes log directory" {
    mkdir -p "$HOME/.local/share/claude-sandbox"
    echo "log line" > "$HOME/.local/share/claude-sandbox/claude-sandbox.log"
    run_uninstall
    [ ! -d "$HOME/.local/share/claude-sandbox" ]
}

# ── Completion removal ────────────────────────────────────────────────────────

@test "uninstall removes bash completion file" {
    mkdir -p "$HOME/.local/share/bash-completion/completions"
    touch "$HOME/.local/share/bash-completion/completions/claude-sandbox"
    run_uninstall
    [ ! -f "$HOME/.local/share/bash-completion/completions/claude-sandbox" ]
}

@test "uninstall removes bashrc.d completion source" {
    mkdir -p "$HOME/.bashrc.d"
    touch "$HOME/.bashrc.d/claude-sandbox"
    run_uninstall
    [ ! -f "$HOME/.bashrc.d/claude-sandbox" ]
}

@test "uninstall removes zfunc completion file" {
    mkdir -p "$HOME/.zfunc"
    touch "$HOME/.zfunc/_claude-sandbox"
    run_uninstall
    [ ! -f "$HOME/.zfunc/_claude-sandbox" ]
}

# ── PATH line removal ─────────────────────────────────────────────────────────

@test "uninstall removes PATH export from .bashrc" {
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    run_uninstall
    ! grep -q '\.local/bin.*PATH' "$HOME/.bashrc"
}

@test "uninstall removes PATH export from .zshrc" {
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    run_uninstall
    ! grep -q '\.local/bin.*PATH' "$HOME/.zshrc"
}

# ── Projects directory ────────────────────────────────────────────────────────

@test "uninstall keeps projects directory by default" {
    mkdir -p "$BASE/my-app/dev"
    run_uninstall
    [ -d "$BASE" ]
}

@test "uninstall removes projects directory with --remove-projects flag" {
    mkdir -p "$BASE/my-app/dev"
    run_uninstall --remove-projects
    [ ! -d "$BASE" ]
}

@test "uninstall shows projects will be kept when no flag given" {
    run_uninstall
    [[ "$output" == *"will be kept"* ]]
}

@test "uninstall lists projects in removal summary when --remove-projects given" {
    run_uninstall --remove-projects
    [[ "$output" == *"Projects:"* ]]
}

# ── Binary removal ────────────────────────────────────────────────────────────

@test "uninstall removes the binary" {
    run_uninstall
    [ ! -f "$HOME/.local/bin/claude-sandbox" ]
}

@test "uninstall prints Uninstalled on success" {
    run_uninstall
    [[ "$output" == *"Uninstalled."* ]]
}

# ── No init required ──────────────────────────────────────────────────────────

@test "uninstall works without config file" {
    rm -f "$HOME/.config/claude-sandbox/config"
    local stdin_file; stdin_file="$(mktemp)"
    printf 'yes\n' > "$stdin_file"
    run "$SCRIPT" uninstall < "$stdin_file"
    rm -f "$stdin_file"
    [ "$status" -eq 0 ]
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "uninstall is listed in help output" {
    run "$SCRIPT" help
    [[ "$output" == *"uninstall"* ]]
}
