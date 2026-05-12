#!/usr/bin/env bats
# Tests for the snapshot subcommand (create, list, restore, remove).

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
    echo "hello" > "$BASE/$project/dev/file.txt"
    echo "state" > "$BASE/$project/container/state.txt"
    cat > "$BASE/$project/sandbox.conf" <<EOF
# Claude sandbox configuration for project: $project
SKIP_PERMISSIONS=true
EOF
}

# ── snapshot create ───────────────────────────────────────────────────────────

@test "snapshot create requires a project name" {
    run "$SCRIPT" snapshot
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "snapshot create fails if project does not exist" {
    run "$SCRIPT" snapshot no-such-project
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "snapshot create creates snapshot directory" {
    make_project my-app
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 0 ]
    [ -d "$BASE/my-app/snapshots/my-snap" ]
}

@test "snapshot create archives dev directory" {
    make_project my-app
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 0 ]
    [ -f "$BASE/my-app/snapshots/my-snap/dev.tar.gz" ]
}

@test "snapshot create archives container directory" {
    make_project my-app
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 0 ]
    [ -f "$BASE/my-app/snapshots/my-snap/container.tar.gz" ]
}

@test "snapshot create copies sandbox.conf" {
    make_project my-app
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 0 ]
    [ -f "$BASE/my-app/snapshots/my-snap/sandbox.conf" ]
}

@test "snapshot create writes snapshot.meta" {
    make_project my-app
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 0 ]
    [ -f "$BASE/my-app/snapshots/my-snap/snapshot.meta" ]
    grep -q "^SNAPSHOT_DATE=" "$BASE/my-app/snapshots/my-snap/snapshot.meta"
}

@test "snapshot create uses timestamp as name when none given" {
    make_project my-app
    run "$SCRIPT" snapshot my-app
    [ "$status" -eq 0 ]
    local count
    count=$(find "$BASE/my-app/snapshots" -mindepth 1 -maxdepth 1 -type d | wc -l)
    [ "$count" -eq 1 ]
}

@test "snapshot create fails if snapshot already exists" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "snapshot create prints snapshot name and size" {
    make_project my-app
    run "$SCRIPT" snapshot my-app my-snap
    [ "$status" -eq 0 ]
    [[ "$output" == *"my-snap"* ]]
    [[ "$output" == *"Size"* ]]
}

# ── snapshot list ─────────────────────────────────────────────────────────────

@test "snapshot list requires a project name" {
    run "$SCRIPT" snapshot list
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "snapshot list fails if project does not exist" {
    run "$SCRIPT" snapshot list no-such-project
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "snapshot list shows message when no snapshots exist" {
    make_project my-app
    run "$SCRIPT" snapshot list my-app
    [ "$status" -eq 0 ]
    [[ "$output" == *"No snapshots found"* ]]
}

@test "snapshot list shows created snapshot" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run "$SCRIPT" snapshot list my-app
    [ "$status" -eq 0 ]
    [[ "$output" == *"my-snap"* ]]
}

@test "snapshot list shows multiple snapshots" {
    make_project my-app
    "$SCRIPT" snapshot my-app snap-one
    "$SCRIPT" snapshot my-app snap-two
    run "$SCRIPT" snapshot list my-app
    [ "$status" -eq 0 ]
    [[ "$output" == *"snap-one"* ]]
    [[ "$output" == *"snap-two"* ]]
}

@test "snapshot list shows date from metadata" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run "$SCRIPT" snapshot list my-app
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

# ── snapshot restore ──────────────────────────────────────────────────────────

@test "snapshot restore requires project and snapshot name" {
    run "$SCRIPT" snapshot restore
    [ "$status" -eq 1 ]
    [[ "$output" == *"project and snapshot name required"* ]]
}

@test "snapshot restore requires snapshot name" {
    make_project my-app
    run "$SCRIPT" snapshot restore my-app
    [ "$status" -eq 1 ]
    [[ "$output" == *"project and snapshot name required"* ]]
}

@test "snapshot restore fails if project does not exist" {
    run "$SCRIPT" snapshot restore no-such-project my-snap
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "snapshot restore fails if snapshot does not exist" {
    make_project my-app
    run "$SCRIPT" snapshot restore my-app no-such-snap
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "snapshot restore auto-saves current state before restoring" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run "$SCRIPT" snapshot restore my-app my-snap
    [ "$status" -eq 0 ]
    local count
    count=$(find "$BASE/my-app/snapshots" -mindepth 1 -maxdepth 1 -type d -name "pre-restore-*" | wc -l)
    [ "$count" -eq 1 ]
}

@test "snapshot restore restores dev directory contents" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    echo "modified" > "$BASE/my-app/dev/file.txt"
    "$SCRIPT" snapshot restore my-app my-snap
    [ "$(cat "$BASE/my-app/dev/file.txt")" = "hello" ]
}

@test "snapshot restore restores container directory contents" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    echo "modified" > "$BASE/my-app/container/state.txt"
    "$SCRIPT" snapshot restore my-app my-snap
    [ "$(cat "$BASE/my-app/container/state.txt")" = "state" ]
}

@test "snapshot restore restores sandbox.conf" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    echo "SKIP_PERMISSIONS=false" > "$BASE/my-app/sandbox.conf"
    "$SCRIPT" snapshot restore my-app my-snap
    grep -q "^SKIP_PERMISSIONS=true" "$BASE/my-app/sandbox.conf"
}

@test "snapshot restore prints restored snapshot name" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run "$SCRIPT" snapshot restore my-app my-snap
    [ "$status" -eq 0 ]
    [[ "$output" == *"Restored: my-snap"* ]]
}

@test "snapshot restore prints pre-restore backup name" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run "$SCRIPT" snapshot restore my-app my-snap
    [ "$status" -eq 0 ]
    [[ "$output" == *"pre-restore-"* ]]
}

# ── snapshot remove ───────────────────────────────────────────────────────────

@test "snapshot remove requires project and snapshot name" {
    run "$SCRIPT" snapshot remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"project and snapshot name required"* ]]
}

@test "snapshot remove fails if project does not exist" {
    run "$SCRIPT" snapshot remove no-such-project my-snap
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "snapshot remove fails if snapshot does not exist" {
    make_project my-app
    run "$SCRIPT" snapshot remove my-app no-such-snap
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "snapshot remove deletes snapshot when confirmed" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run bash -c "echo y | \"$SCRIPT\" snapshot remove my-app my-snap"
    [ "$status" -eq 0 ]
    [ ! -d "$BASE/my-app/snapshots/my-snap" ]
}

@test "snapshot remove cancels when user says no" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run bash -c "echo n | \"$SCRIPT\" snapshot remove my-app my-snap"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
    [ -d "$BASE/my-app/snapshots/my-snap" ]
}

@test "snapshot remove prints removed snapshot name" {
    make_project my-app
    "$SCRIPT" snapshot my-app my-snap
    run bash -c "echo y | \"$SCRIPT\" snapshot remove my-app my-snap"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed snapshot: my-snap"* ]]
}

@test "snapshot is listed in help output" {
    run "$SCRIPT" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"snapshot"* ]]
}
