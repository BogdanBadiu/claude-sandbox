#!/usr/bin/env bats
# Tests for the link subcommand.
# ssh-keygen is mocked via mock_ssh_keygen.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"
MOCK_SSH_KEYGEN_SRC="$BATS_TEST_DIRNAME/mock_ssh_keygen"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"

    export BASE
    BASE="$(mktemp -d)"

    export MOCK_BIN
    MOCK_BIN="$(mktemp -d)"

    # ssh-keygen mock
    cp "$MOCK_SSH_KEYGEN_SRC" "$MOCK_BIN/ssh-keygen"
    chmod +x "$MOCK_BIN/ssh-keygen"

    export PATH="$MOCK_BIN:$PATH"

    export MOCK_COMMAND_LOG
    MOCK_COMMAND_LOG="$(mktemp)"

    # Write a config so require_init passes
    mkdir -p "$HOME/.config/claude-sandbox"
    echo "CLAUDE_SANDBOX_BASE=\"$BASE\"" > "$HOME/.config/claude-sandbox/config"

    export LOG_FILE="$HOME/.local/share/claude-sandbox/claude-sandbox.log"
}

teardown() {
    rm -rf "$HOME" "$BASE" "$MOCK_BIN" "$MOCK_COMMAND_LOG"
    export HOME="$REAL_HOME"
}

# Helper: create a project directory structure
make_project() {
    local project="$1"
    mkdir -p "$BASE/$project/container"
    mkdir -p "$BASE/$project/dev"
}

keygen_log_has() { grep -qF -- "$1" "$MOCK_COMMAND_LOG"; }

# ── Key generation ────────────────────────────────────────────────────────────

@test "link git creates .ssh directory in container home" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [ -d "$BASE/my-app/container/.ssh" ]
}

@test "link git sets 700 permissions on .ssh directory" {
    make_project my-app
    run "$SCRIPT" link git my-app
    local perms
    perms=$(stat -c '%a' "$BASE/my-app/container/.ssh")
    [ "$perms" = "700" ]
}

@test "link git generates a keypair" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [ -f "$BASE/my-app/container/.ssh/id_ed25519" ]
    [ -f "$BASE/my-app/container/.ssh/id_ed25519.pub" ]
}

@test "link git calls ssh-keygen with ed25519 type" {
    make_project my-app
    run "$SCRIPT" link git my-app
    keygen_log_has "ssh-keygen"
    keygen_log_has "ed25519"
}

@test "link git labels the key with the project name" {
    make_project my-app
    run "$SCRIPT" link git my-app
    keygen_log_has "claude-sandbox/my-app"
}

@test "link git prints the public key" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [[ "$output" == *"ssh-ed25519"* ]]
}

@test "link git shows GitHub deploy key URL" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [[ "$output" == *"github.com"* ]]
}

@test "link git shows GitLab deploy key URL" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [[ "$output" == *"gitlab.com"* ]]
}

@test "link git mentions write access option" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [[ "$output" == *"write access"* ]]
}

@test "link git exits 0 on success" {
    make_project my-app
    run "$SCRIPT" link git my-app
    [ "$status" -eq 0 ]
}

# ── SSH config ────────────────────────────────────────────────────────────────

@test "link git writes ssh config for github.com" {
    make_project my-app
    run "$SCRIPT" link git my-app
    grep -q "Host github.com" "$BASE/my-app/container/.ssh/config"
}

@test "link git writes ssh config for gitlab.com" {
    make_project my-app
    run "$SCRIPT" link git my-app
    grep -q "Host gitlab.com" "$BASE/my-app/container/.ssh/config"
}

@test "link git ssh config uses StrictHostKeyChecking accept-new" {
    make_project my-app
    run "$SCRIPT" link git my-app
    grep -q "StrictHostKeyChecking accept-new" "$BASE/my-app/container/.ssh/config"
}

@test "link git does not overwrite existing ssh config" {
    make_project my-app
    mkdir -p "$BASE/my-app/container/.ssh"
    echo "Host custom.example.com" > "$BASE/my-app/container/.ssh/config"
    run "$SCRIPT" link git my-app
    grep -q "Host custom.example.com" "$BASE/my-app/container/.ssh/config"
}

# ── Idempotency ───────────────────────────────────────────────────────────────

@test "link git does not regenerate key if already exists" {
    make_project my-app
    # Pre-create a key
    mkdir -p "$BASE/my-app/container/.ssh"
    echo "existing-key" > "$BASE/my-app/container/.ssh/id_ed25519"
    echo "existing-pub" > "$BASE/my-app/container/.ssh/id_ed25519.pub"
    run "$SCRIPT" link git my-app
    grep -q "existing-key" "$BASE/my-app/container/.ssh/id_ed25519"
}

@test "link git prints existing key when key already exists" {
    make_project my-app
    mkdir -p "$BASE/my-app/container/.ssh"
    echo "existing-key" > "$BASE/my-app/container/.ssh/id_ed25519"
    echo "ssh-ed25519 EXISTING_PUB_KEY" > "$BASE/my-app/container/.ssh/id_ed25519.pub"
    run "$SCRIPT" link git my-app
    [[ "$output" == *"EXISTING_PUB_KEY"* ]]
}

@test "link git reports key already exists" {
    make_project my-app
    mkdir -p "$BASE/my-app/container/.ssh"
    echo "key" > "$BASE/my-app/container/.ssh/id_ed25519"
    echo "pub" > "$BASE/my-app/container/.ssh/id_ed25519.pub"
    run "$SCRIPT" link git my-app
    [[ "$output" == *"already exists"* ]]
}

# ── Error cases ───────────────────────────────────────────────────────────────

@test "link git fails if project does not exist" {
    run "$SCRIPT" link git no-such-project
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "link git error mentions list command" {
    run "$SCRIPT" link git no-such-project
    [[ "$output" == *"claude-sandbox list"* ]]
}

@test "link git fails if no project name given" {
    run "$SCRIPT" link git
    [ "$status" -eq 1 ]
    [[ "$output" == *"no project name"* ]]
}

@test "link with unknown service exits with error" {
    make_project my-app
    run "$SCRIPT" link svn my-app
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown link type"* ]]
}

@test "link with no subcommand exits with error" {
    run "$SCRIPT" link
    [ "$status" -eq 1 ]
}

@test "link requires init" {
    rm "$HOME/.config/claude-sandbox/config"
    run "$SCRIPT" link git my-app
    [ "$status" -eq 1 ]
    [[ "$output" == *"not initialized"* ]]
}

# ── Logging ───────────────────────────────────────────────────────────────────

@test "link git logs start at INFO level" {
    make_project my-app
    run "$SCRIPT" link git my-app
    grep -qF "[INFO ] cmd_link_git: setting up deploy key" "$LOG_FILE"
}

@test "link git logs completion at INFO level" {
    make_project my-app
    run "$SCRIPT" link git my-app
    grep -qF "[INFO ] cmd_link_git: deploy key setup complete" "$LOG_FILE"
}

@test "link git logs error when project not found" {
    run "$SCRIPT" link git no-such-project
    grep -qF "[ERROR]" "$LOG_FILE"
}

# ── Help ──────────────────────────────────────────────────────────────────────

@test "link is listed in help output" {
    run "$SCRIPT" help
    [[ "$output" == *"link"* ]]
}

# ── link containerfile ────────────────────────────────────────────────────────

@test "link containerfile requires suffix" {
    run "$SCRIPT" link containerfile
    [ "$status" -eq 1 ]
    [[ "$output" == *"no suffix given"* ]]
}

@test "link containerfile requires path" {
    run "$SCRIPT" link containerfile node
    [ "$status" -eq 1 ]
    [[ "$output" == *"no path given"* ]]
}

@test "link containerfile fails when file does not exist" {
    run "$SCRIPT" link containerfile node /nonexistent/Containerfile
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "link containerfile creates symlink in config dir" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    run "$SCRIPT" link containerfile node "$cfile"
    [ "$status" -eq 0 ]
    [ -L "$HOME/.config/claude-sandbox/Containerfile.node" ]
    rm -f "$cfile"
}

@test "link containerfile symlink points to source file" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    "$SCRIPT" link containerfile node "$cfile"
    local target; target="$(realpath "$HOME/.config/claude-sandbox/Containerfile.node")"
    [ "$target" = "$(realpath "$cfile")" ]
    rm -f "$cfile"
}

@test "link containerfile prints linked path" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    run "$SCRIPT" link containerfile myimg "$cfile"
    [[ "$output" == *"Linked:"* ]]
    rm -f "$cfile"
}

@test "link containerfile prints build hint" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    run "$SCRIPT" link containerfile myimg "$cfile"
    [[ "$output" == *"claude-sandbox build myimg"* ]]
    rm -f "$cfile"
}

@test "link containerfile prints new project hint" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    run "$SCRIPT" link containerfile myimg "$cfile"
    [[ "$output" == *"claude-sandbox new"* ]]
    [[ "$output" == *"myimg"* ]]
    rm -f "$cfile"
}

@test "link containerfile is idempotent when already linked to same path" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    "$SCRIPT" link containerfile node "$cfile"
    run "$SCRIPT" link containerfile node "$cfile"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already linked"* ]]
    rm -f "$cfile"
}

@test "link containerfile fails when destination already exists with different path" {
    local cfile1; cfile1="$(mktemp)"
    local cfile2; cfile2="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile1"
    echo "FROM claude-ubuntu" > "$cfile2"
    "$SCRIPT" link containerfile node "$cfile1"
    run "$SCRIPT" link containerfile node "$cfile2"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
    rm -f "$cfile1" "$cfile2"
}

@test "link containerfile logs info on success" {
    local cfile; cfile="$(mktemp)"
    echo "FROM claude-ubuntu" > "$cfile"
    run "$SCRIPT" link containerfile logsuffix "$cfile"
    grep -q "cmd_link_containerfile" "$HOME/.local/share/claude-sandbox/claude-sandbox.log"
    rm -f "$cfile"
}
