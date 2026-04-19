#!/usr/bin/env bats
# Tests for the status subcommand output structure.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"
}

teardown() {
    rm -rf "$HOME"
    export HOME="$REAL_HOME"
}

@test "status exits 0" {
    run "$SCRIPT" status
    [ "$status" -eq 0 ]
}

@test "status shows version" {
    run "$SCRIPT" status
    [[ "$output" == *"claude-sandbox v"* ]]
}

@test "status shows config file path" {
    run "$SCRIPT" status
    [[ "$output" == *".config/claude-sandbox/config"* ]]
}

@test "status mentions podman" {
    run "$SCRIPT" status
    [[ "$output" == *"Podman:"* ]]
}

@test "status shows shell" {
    run "$SCRIPT" status
    [[ "$output" == *"Shell:"* ]]
}

@test "status shows container user" {
    run "$SCRIPT" status
    [[ "$output" == *"Container user: sandbox"* ]]
}

@test "help shows all subcommands" {
    run "$SCRIPT" help
    [ "$status" -eq 0 ]
    for cmd in init new start stop list build remove status help; do
        [[ "$output" == *"$cmd"* ]] || {
            echo "missing subcommand: $cmd"
            return 1
        }
    done
}

@test "no args shows help" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "--help flag shows help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
