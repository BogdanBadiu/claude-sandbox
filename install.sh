#!/usr/bin/env bash
# claude-sandbox installer
# Usage: curl -fsSL <url>/install.sh | bash
# Or:    bash install.sh [--prefix <dir>]
#
# Installs claude-sandbox binary and bash completion to ~/.local/bin (or --prefix dir).
# After installation, run: claude-sandbox init

set -euo pipefail

REPO_URL="${CLAUDE_SANDBOX_REPO_URL:-https://raw.githubusercontent.com/bogdanb-dev/claude-sandbox/main}"
DEFAULT_PREFIX="${HOME}/.local/bin"

# ── Argument parsing ──────────────────────────────────────────────────────────

PREFIX="$DEFAULT_PREFIX"
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            PREFIX="${1:?--prefix requires a directory argument}"
            ;;
        --help|-h)
            echo "Usage: install.sh [--prefix <dir>]"
            echo ""
            echo "Installs claude-sandbox to PREFIX (default: ~/.local/bin)."
            echo "After installation, run: claude-sandbox init"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run 'install.sh --help' for usage." >&2
            exit 1
            ;;
    esac
    shift
done

# ── Ensure native curl is available (Ubuntu ships Snap curl which can't write to ~/.local) ──

if command -v curl &>/dev/null && [[ "$(command -v curl)" == */snap/* ]]; then
    echo "Note: Snap curl detected — installing native curl..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y curl >/dev/null
    fi
fi

# ── Detect whether we're running from a local clone or via curl | bash ────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-install.sh}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_SCRIPT="${SCRIPT_DIR}/src/claude-sandbox"
LOCAL_COMPLETION="${SCRIPT_DIR}/completions/bash"

# ── Install binary ────────────────────────────────────────────────────────────

mkdir -p "$PREFIX"

if [ -f "$LOCAL_SCRIPT" ]; then
    install -m755 "$LOCAL_SCRIPT" "${PREFIX}/claude-sandbox"
else
    if ! command -v curl &>/dev/null; then
        echo "Error: curl is required to download claude-sandbox." >&2
        echo "Install curl and try again, or clone the repository manually." >&2
        exit 1
    fi
    echo "Downloading claude-sandbox..."
    curl -fsSL "${REPO_URL}/src/claude-sandbox" -o "${PREFIX}/claude-sandbox"
    chmod 755 "${PREFIX}/claude-sandbox"
fi

echo "Installed: ${PREFIX}/claude-sandbox"

# ── Install bash completion ───────────────────────────────────────────────────

COMP_DIR="${HOME}/.local/share/bash-completion/completions"
COMP_FILE="${COMP_DIR}/claude-sandbox"
mkdir -p "$COMP_DIR"

if [ -f "$LOCAL_COMPLETION" ]; then
    install -m644 "$LOCAL_COMPLETION" "$COMP_FILE"
else
    curl -fsSL "${REPO_URL}/completions/bash" -o "$COMP_FILE"
    chmod 644 "$COMP_FILE"
fi

echo "Completion: ${COMP_FILE}"

# ── PATH and completion source lines ─────────────────────────────────────────

BASHRC_UPDATED=false
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ ! -f "$rc" ]; then continue; fi
    CHANGED=false
    if ! grep -q "$PREFIX" "$rc"; then
        echo "export PATH=\"${PREFIX}:\$PATH\"" >> "$rc"
        CHANGED=true
    fi
    if ! grep -qF "$COMP_FILE" "$rc"; then
        echo "source ${COMP_FILE}" >> "$rc"
        CHANGED=true
    fi
    if $CHANGED; then
        echo "Updated: ${rc}"
        BASHRC_UPDATED=true
    fi
done

echo ""
if $BASHRC_UPDATED; then
    echo "Run the following to apply in this session:"
    echo "  source ~/.bashrc"
    echo ""
fi
echo "Next step: run 'claude-sandbox init' to complete setup."
