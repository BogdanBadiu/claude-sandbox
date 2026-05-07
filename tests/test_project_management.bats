#!/usr/bin/env bats
# Tests for new, list, and remove subcommands.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"
    export BASE
    BASE="$(mktemp -d)"
    mkdir -p "$HOME/.config/claude-sandbox"
    echo "CLAUDE_SANDBOX_BASE=$BASE" > "$HOME/.config/claude-sandbox/config"
}

teardown() {
    rm -rf "$HOME" "$BASE"
    export HOME="$REAL_HOME"
}

# ── new ───────────────────────────────────────────────────────────────────────

@test "new creates dev and container directories" {
    run "$SCRIPT" new my-app
    [ "$status" -eq 0 ]
    [ -d "$BASE/my-app/dev" ]
    [ -d "$BASE/my-app/container" ]
}

@test "new creates sandbox.conf" {
    run "$SCRIPT" new my-app
    [ -f "$BASE/my-app/sandbox.conf" ]
}

@test "new without --safe sets SKIP_PERMISSIONS=true" {
    run "$SCRIPT" new my-app
    grep -q "^SKIP_PERMISSIONS=true" "$BASE/my-app/sandbox.conf"
}

@test "new --safe sets SKIP_PERMISSIONS=false" {
    run "$SCRIPT" new my-app --safe
    grep -q "^SKIP_PERMISSIONS=false" "$BASE/my-app/sandbox.conf"
}

@test "new with image suffix writes IMAGE_SUFFIX uncommented" {
    run "$SCRIPT" new my-app postgres
    grep -q "^IMAGE_SUFFIX=postgres" "$BASE/my-app/sandbox.conf"
}

@test "new without image suffix leaves IMAGE_SUFFIX commented" {
    run "$SCRIPT" new my-app
    # should not have an uncommented IMAGE_SUFFIX line
    run grep -c "^IMAGE_SUFFIX=" "$BASE/my-app/sandbox.conf"
    [ "$output" -eq 0 ]
}

@test "new with image and --safe works together" {
    run "$SCRIPT" new my-app postgres --safe
    [ "$status" -eq 0 ]
    grep -q "^IMAGE_SUFFIX=postgres" "$BASE/my-app/sandbox.conf"
    grep -q "^SKIP_PERMISSIONS=false" "$BASE/my-app/sandbox.conf"
}

@test "new fails if project already exists" {
    mkdir -p "$BASE/existing"
    run "$SCRIPT" new existing
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "new fails if no project name given" {
    run "$SCRIPT" new
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "new fails with unknown flag" {
    run "$SCRIPT" new my-app --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown flag"* ]]
}

@test "new fails if base dir does not exist" {
    rm -rf "$BASE"
    run "$SCRIPT" new my-app
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "new prints next-step hint" {
    run "$SCRIPT" new my-app
    [[ "$output" == *"claude-sandbox start my-app"* ]]
}

# ── list ─────────────────────────────────────────────────────────────────────

@test "list shows no projects message when base is empty" {
    run "$SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No projects found"* ]]
}

@test "list shows created project" {
    "$SCRIPT" new alpha >/dev/null
    run "$SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
}

@test "list shows multiple projects" {
    "$SCRIPT" new alpha >/dev/null
    "$SCRIPT" new beta >/dev/null
    run "$SCRIPT" list
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

@test "list shows base image for project without image suffix" {
    "$SCRIPT" new plain >/dev/null
    run "$SCRIPT" list
    [[ "$output" == *"claude-ubuntu"* ]]
}

@test "list shows extended image for project with image suffix" {
    "$SCRIPT" new db-app postgres >/dev/null
    run "$SCRIPT" list
    [[ "$output" == *"claude-ubuntu-postgres"* ]]
}

@test "list fails if base dir does not exist" {
    rm -rf "$BASE"
    run "$SCRIPT" list
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

# ── remove ────────────────────────────────────────────────────────────────────

@test "remove fails if project does not exist" {
    run "$SCRIPT" remove ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "remove fails if no project name given" {
    run "$SCRIPT" remove
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "remove with wrong confirmation cancels" {
    "$SCRIPT" new to-keep >/dev/null
    run bash -c "echo 'wrong' | $SCRIPT remove to-keep"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cancelled"* ]]
    [ -d "$BASE/to-keep" ]
}

@test "remove with correct confirmation deletes project directory" {
    "$SCRIPT" new to-delete >/dev/null
    run bash -c "echo 'to-delete' | $SCRIPT remove to-delete"
    [ "$status" -eq 0 ]
    [ ! -d "$BASE/to-delete" ]
}

@test "remove prints removed message on success" {
    "$SCRIPT" new bye >/dev/null
    run bash -c "echo 'bye' | $SCRIPT remove bye"
    [[ "$output" == *"Removed project: bye"* ]]
}

@test "remove hints list command when project missing" {
    run "$SCRIPT" remove ghost
    [[ "$output" == *"claude-sandbox list"* ]]
}

# ── shell ─────────────────────────────────────────────────────────────────────

@test "shell fails if no project name given" {
    run "$SCRIPT" shell
    [ "$status" -eq 1 ]
    [[ "$output" == *"project name required"* ]]
}

@test "shell fails if project does not exist" {
    run "$SCRIPT" shell ghost
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "shell hints new command when project missing" {
    run "$SCRIPT" shell ghost
    [[ "$output" == *"claude-sandbox new ghost"* ]]
}
