#!/usr/bin/env bats
# Tests for start and stop subcommands.
# Podman is mocked via tests/mock_podman — no real containers are touched.

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

    # Create a temp bin dir with the mock named "podman" and prepend to PATH
    export MOCK_BIN
    MOCK_BIN="$(mktemp -d)"
    cp "$MOCK_SRC" "$MOCK_BIN/podman"
    chmod +x "$MOCK_BIN/podman"
    export PATH="$MOCK_BIN:$PATH"

    # Each test gets its own log file
    export MOCK_PODMAN_LOG
    MOCK_PODMAN_LOG="$(mktemp)"

    # Default: no running containers, no stopped containers, base image exists
    export MOCK_RUNNING=""
    export MOCK_STOPPED=""
    export MOCK_IMAGES="claude-ubuntu"
    export MOCK_PODMAN_FAIL=""
}

teardown() {
    rm -rf "$HOME" "$BASE" "$MOCK_PODMAN_LOG" "$MOCK_BIN"
    export HOME="$REAL_HOME"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

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

podman_log() { cat "$MOCK_PODMAN_LOG"; }

log_has() { grep -qF -- "$1" "$MOCK_PODMAN_LOG"; }

# ── start: argument validation ────────────────────────────────────────────────

@test "start requires a project name" {
    run "$SCRIPT" start
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "start fails for non-existent project" {
    run "$SCRIPT" start ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
    [[ "$output" == *"claude-sandbox new ghost"* ]]
}

# ── start: image selection ────────────────────────────────────────────────────

@test "start uses base image when no suffix configured" {
    make_project my-app
    run "$SCRIPT" start my-app
    log_has "image exists claude-ubuntu"
}

@test "start uses IMAGE_SUFFIX from sandbox.conf when set" {
    make_project db-app
    echo "IMAGE_SUFFIX=postgres" >> "$BASE/db-app/sandbox.conf"
    export MOCK_IMAGES="claude-ubuntu claude-ubuntu-postgres"
    run "$SCRIPT" start db-app
    log_has "image exists claude-ubuntu-postgres"
}

@test "start uses convention image when it exists and no suffix in conf" {
    make_project web-app
    export MOCK_IMAGES="claude-ubuntu claude-ubuntu-web-app"
    run "$SCRIPT" start web-app
    log_has "image exists claude-ubuntu-web-app"
}

@test "start prefers IMAGE_SUFFIX from conf over convention image" {
    make_project mixed
    echo "IMAGE_SUFFIX=custom" >> "$BASE/mixed/sandbox.conf"
    export MOCK_IMAGES="claude-ubuntu claude-ubuntu-mixed claude-ubuntu-custom"
    run "$SCRIPT" start mixed
    log_has "image exists claude-ubuntu-custom"
}

@test "start errors when selected image does not exist" {
    make_project db-app
    echo "IMAGE_SUFFIX=postgres" >> "$BASE/db-app/sandbox.conf"
    # MOCK_IMAGES only has base — postgres image absent
    run "$SCRIPT" start db-app
    [ "$status" -eq 1 ]
    [[ "$output" == *"image 'claude-ubuntu-postgres' not found"* ]]
}

# ── start: container states ───────────────────────────────────────────────────

@test "start missing container runs podman run" {
    make_project new-app
    run "$SCRIPT" start new-app
    [ "$status" -eq 0 ]
    log_has "run -d"
    log_has "--name claude-new-app"
}

@test "start missing container passes correct volume mounts" {
    make_project vol-app
    run "$SCRIPT" start vol-app
    log_has "/home/sandbox:Z"
    log_has "/home/sandbox/dev:Z"
}

@test "start missing container passes correct resource limits" {
    make_project res-app
    run "$SCRIPT" start res-app
    log_has "--pids-limit 4096"
    log_has "--cpus 4"
    log_has "--memory 8g"
}

@test "start missing container passes default ports" {
    make_project port-app
    run "$SCRIPT" start port-app
    log_has "-p 3000:3000"
    log_has "-p 5173:5173"
    log_has "-p 8080:8080"
}

@test "start missing container passes extra ports from sandbox.conf" {
    make_project extra-port-app
    sed -i 's/# EXTRA_PORTS=/EXTRA_PORTS=9000 9001/' "$BASE/extra-port-app/sandbox.conf"
    run "$SCRIPT" start extra-port-app
    log_has "-p 9000:9000"
    log_has "-p 9001:9001"
}

@test "start stopped container resumes with podman start" {
    make_project paused-app
    export MOCK_STOPPED="claude-paused-app"
    run "$SCRIPT" start paused-app
    [ "$status" -eq 0 ]
    log_has "start claude-paused-app"
    [[ "$output" == *"Resuming"* ]]
}

@test "start stopped container does not run podman run" {
    make_project paused-app
    export MOCK_STOPPED="claude-paused-app"
    run "$SCRIPT" start paused-app
    ! log_has "run -d"
}

@test "start running container skips podman run and podman start" {
    make_project live-app
    export MOCK_RUNNING="claude-live-app"
    run "$SCRIPT" start live-app
    [ "$status" -eq 0 ]
    ! log_has "run -d"
    ! log_has "start claude-live-app"
}

# ── start: exec into container ────────────────────────────────────────────────

@test "start execs into container via podman exec" {
    make_project exec-app
    run "$SCRIPT" start exec-app
    log_has "exec -it -w /home/sandbox/dev claude-exec-app"
}

@test "start passes --dangerously-skip-permissions when SKIP_PERMISSIONS=true" {
    make_project skip-app
    run "$SCRIPT" start skip-app
    log_has "--dangerously-skip-permissions"
}

@test "start omits --dangerously-skip-permissions when SKIP_PERMISSIONS=false" {
    make_project safe-app
    sed -i 's/SKIP_PERMISSIONS=true/SKIP_PERMISSIONS=false/' "$BASE/safe-app/sandbox.conf"
    run "$SCRIPT" start safe-app
    ! log_has "--dangerously-skip-permissions"
}

@test "start prints safe mode note when SKIP_PERMISSIONS=false" {
    make_project safe-app
    sed -i 's/SKIP_PERMISSIONS=true/SKIP_PERMISSIONS=false/' "$BASE/safe-app/sandbox.conf"
    run "$SCRIPT" start safe-app
    [[ "$output" == *"safe mode"* ]]
}

@test "start prints no note when SKIP_PERMISSIONS=true" {
    make_project normal-app
    run "$SCRIPT" start normal-app
    [[ "$output" != *"safe mode"* ]]
}

@test "start defaults to skip-permissions when SKIP_PERMISSIONS absent from conf" {
    make_project no-conf-app
    mkdir -p "$BASE/no-conf-app/dev" "$BASE/no-conf-app/container"
    # write conf without SKIP_PERMISSIONS line
    echo "# IMAGE_SUFFIX=" > "$BASE/no-conf-app/sandbox.conf"
    run "$SCRIPT" start no-conf-app
    log_has "--dangerously-skip-permissions"
}

# ── stop ─────────────────────────────────────────────────────────────────────

@test "stop requires a project name" {
    run "$SCRIPT" stop
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "stop fails for non-existent project" {
    run "$SCRIPT" stop ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "stop running container calls podman stop" {
    make_project live-app
    export MOCK_RUNNING="claude-live-app"
    run "$SCRIPT" stop live-app
    [ "$status" -eq 0 ]
    log_has "stop claude-live-app"
    [[ "$output" == *"Stopped"* ]]
}

@test "stop already-stopped container prints message without error" {
    make_project paused-app
    export MOCK_STOPPED="claude-paused-app"
    run "$SCRIPT" stop paused-app
    [ "$status" -eq 0 ]
    [[ "$output" == *"already stopped"* ]]
    ! log_has "stop claude-paused-app"
}

@test "stop missing container prints message without error" {
    make_project new-app
    run "$SCRIPT" stop new-app
    [ "$status" -eq 0 ]
    [[ "$output" == *"No container found"* ]]
}
