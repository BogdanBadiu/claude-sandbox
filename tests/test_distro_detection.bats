#!/usr/bin/env bats
# Tests for detect_distro and detect_selinux.
#
# detect_distro reads $OS_RELEASE_FILE (overridable) — no real /etc/os-release
# is touched. detect_selinux runs getenforce — mocked via a fake binary on PATH.

SCRIPT="$BATS_TEST_DIRNAME/../src/claude-sandbox"

setup() {
    export REAL_HOME="$HOME"
    export HOME
    HOME="$(mktemp -d)"

    # Temp dir for mock os-release files and fake binaries
    export MOCK_DIR
    MOCK_DIR="$(mktemp -d)"

    # Write a minimal config so require_init doesn't block
    mkdir -p "$HOME/.config/claude-sandbox"
    export BASE
    BASE="$(mktemp -d)"
    echo "CLAUDE_SANDBOX_BASE=$BASE" > "$HOME/.config/claude-sandbox/config"
}

teardown() {
    rm -rf "$HOME" "$BASE" "$MOCK_DIR"
    export HOME="$REAL_HOME"
}

# ── Helper: write a mock os-release file ─────────────────────────────────────

make_os_release() {
    local id="${1:-}" id_like="${2:-}"
    local file="$MOCK_DIR/os-release"
    {
        [ -n "$id" ]      && echo "ID=${id}"
        [ -n "$id_like" ] && echo "ID_LIKE=${id_like}"
    } > "$file"
    echo "$file"
}

make_os_release_quoted() {
    local id="${1:-}" id_like="${2:-}"
    local file="$MOCK_DIR/os-release-quoted"
    {
        [ -n "$id" ]      && echo "ID=\"${id}\""
        [ -n "$id_like" ] && echo "ID_LIKE=\"${id_like}\""
    } > "$file"
    echo "$file"
}

# Run detect_distro via the script and capture the three globals.
# Usage: run_detect <os-release-file>
# Outputs lines: DISTRO_ID=... PKG_MANAGER=... SELINUX_EXPECTED=...
run_detect() {
    local f="$1"
    OS_RELEASE_FILE="$f" bash -c "
        # Suppress the dispatch section's output (help text etc.)
        { source '$SCRIPT'; } >/dev/null 2>&1 || true
        detect_distro
        echo \"DISTRO_ID=\$DISTRO_ID\"
        echo \"PKG_MANAGER=\$PKG_MANAGER\"
        echo \"SELINUX_EXPECTED=\$SELINUX_EXPECTED\"
    "
}

# ── Fedora / RHEL family ──────────────────────────────────────────────────────

@test "fedora → dnf, selinux expected" {
    f=$(make_os_release "fedora")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=dnf"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "rhel → dnf, selinux expected" {
    f=$(make_os_release "rhel")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=dnf"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "centos → dnf, selinux expected" {
    f=$(make_os_release "centos")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=dnf"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "rocky → dnf, selinux expected" {
    f=$(make_os_release "rocky")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=dnf"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "alma → dnf, selinux expected" {
    f=$(make_os_release "alma")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=dnf"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "fedora → DISTRO_ID set to fedora" {
    f=$(make_os_release "fedora")
    result=$(run_detect "$f")
    [[ "$result" == *"DISTRO_ID=fedora"* ]]
}

# ── Ubuntu / Debian family ────────────────────────────────────────────────────

@test "ubuntu → apt-get, no selinux" {
    f=$(make_os_release "ubuntu")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=false"* ]]
}

@test "debian → apt-get, no selinux" {
    f=$(make_os_release "debian")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=false"* ]]
}

@test "linuxmint → apt-get via ID direct match" {
    f=$(make_os_release "linuxmint")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
}

# ── Arch family ───────────────────────────────────────────────────────────────

@test "arch → pacman, no selinux" {
    f=$(make_os_release "arch")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=pacman"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=false"* ]]
}

@test "manjaro → pacman, no selinux" {
    f=$(make_os_release "manjaro")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=pacman"* ]]
}

# ── openSUSE family ───────────────────────────────────────────────────────────

@test "opensuse-leap → zypper, selinux expected" {
    f=$(make_os_release "opensuse-leap")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=zypper"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "opensuse-tumbleweed → zypper, selinux expected" {
    f=$(make_os_release "opensuse-tumbleweed")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=zypper"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "suse → zypper, selinux expected" {
    f=$(make_os_release "suse")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=zypper"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

# ── Alpine ────────────────────────────────────────────────────────────────────

@test "alpine → apk, no selinux" {
    f=$(make_os_release "alpine")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apk"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=false"* ]]
}

# ── ID_LIKE fallback ──────────────────────────────────────────────────────────

@test "unknown ID with ID_LIKE=ubuntu → apt-get" {
    f=$(make_os_release "popos" "ubuntu")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
}

@test "unknown ID with ID_LIKE=debian → apt-get" {
    f=$(make_os_release "kali" "debian")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
}

@test "unknown ID with ID_LIKE contains fedora → dnf" {
    # ID_LIKE can be space-separated, e.g. "fedora linux"
    f=$(make_os_release "custom-rhel" "fedora linux")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=dnf"* ]]
    [[ "$result" == *"SELINUX_EXPECTED=true"* ]]
}

@test "unknown ID with ID_LIKE=arch → pacman" {
    f=$(make_os_release "endeavouros" "arch")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=pacman"* ]]
}

@test "DISTRO_ID is set to the raw ID value even when matched via ID_LIKE" {
    f=$(make_os_release "popos" "ubuntu")
    result=$(run_detect "$f")
    [[ "$result" == *"DISTRO_ID=popos"* ]]
}

# ── Unknown distro ────────────────────────────────────────────────────────────

@test "completely unknown distro → PKG_MANAGER=unknown" {
    f=$(make_os_release "gentoo")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=unknown"* ]]
}

@test "completely unknown distro → SELINUX_EXPECTED=false" {
    f=$(make_os_release "gentoo")
    result=$(run_detect "$f")
    [[ "$result" == *"SELINUX_EXPECTED=false"* ]]
}

@test "missing os-release file → PKG_MANAGER=unknown" {
    result=$(run_detect "/nonexistent/os-release")
    [[ "$result" == *"PKG_MANAGER=unknown"* ]]
}

# ── Quoted values in os-release ───────────────────────────────────────────────

@test "quoted ID value is stripped of quotes" {
    f=$(make_os_release_quoted "ubuntu" "")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
}

@test "quoted ID_LIKE value is stripped of quotes" {
    f=$(make_os_release_quoted "popos" "ubuntu debian")
    result=$(run_detect "$f")
    [[ "$result" == *"PKG_MANAGER=apt-get"* ]]
}

# ── detect_selinux ────────────────────────────────────────────────────────────

# Run detect_selinux with a fake getenforce pointed to by GETENFORCE_CMD.
run_selinux() {
    local fake_output="$1"
    local bin="$MOCK_DIR/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\necho "%s"\n' "$fake_output" > "$bin/getenforce"
    chmod +x "$bin/getenforce"
    GETENFORCE_CMD="$bin/getenforce" bash -c "
        { source '$SCRIPT'; } >/dev/null 2>&1 || true
        detect_selinux
    "
}

# Simulate getenforce not installed by pointing GETENFORCE_CMD at a nonexistent path.
run_selinux_missing() {
    GETENFORCE_CMD="/nonexistent/getenforce" bash -c "
        { source '$SCRIPT'; } >/dev/null 2>&1 || true
        detect_selinux
    "
}

@test "detect_selinux returns enforcing when getenforce says Enforcing" {
    result=$(run_selinux "Enforcing")
    [ "$result" = "enforcing" ]
}

@test "detect_selinux returns permissive when getenforce says Permissive" {
    result=$(run_selinux "Permissive")
    [ "$result" = "permissive" ]
}

@test "detect_selinux returns disabled when getenforce says Disabled" {
    result=$(run_selinux "Disabled")
    [ "$result" = "disabled" ]
}

@test "detect_selinux returns unknown when getenforce not found" {
    result=$(run_selinux_missing)
    [ "$result" = "unknown" ]
}

@test "detect_selinux returns unknown for unexpected getenforce output" {
    result=$(run_selinux "something-weird")
    [ "$result" = "unknown" ]
}

@test "detect_selinux output is lowercase" {
    result=$(run_selinux "Enforcing")
    [[ "$result" == [a-z]* ]]
}
