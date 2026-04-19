# Manual Setup Guide

This guide describes how to set up Claude Code sandboxes by hand. The `claude-sandbox` tool automates everything described here — useful if you want to understand what `claude-sandbox` does under the hood.

A reference guide for setting up isolated, per-project Claude Code sandboxes using Podman and Ubuntu containers on Linux.

---

## Overview

The goal is a setup where each project gets its own isolated container with:
- Its own Claude Code context and configuration
- Its own code directory
- A persistent home directory that survives container restarts
- No access to the rest of your host filesystem

```
YOUR_CLAUDE_SANDBOX_BASE/
├── my-app/
│   ├── dev/          ← your actual code
│   └── container/    ← container's home (Claude config, skills, CLAUDE.md)
├── another-app/
│   ├── dev/
│   └── container/
```

### How images and containers relate

This setup uses a layered image approach:

```
claude-ubuntu (base image)
│   Common tools: Claude Code, git, curl, Node.js, uv, Rust, etc.
│   Built once. Shared by all projects.
│
├── claude-ubuntu-postgres (extended image)  ← FROM claude-ubuntu + postgres tools
├── claude-ubuntu-python   (extended image)  ← FROM claude-ubuntu + python tools
└── claude-ubuntu-webdev   (extended image)  ← FROM claude-ubuntu + web tools

Each image can run many containers:

claude-ubuntu
├── claude-my-app      (container) → mounts .../my-app/
└── claude-website     (container) → mounts .../website/

claude-ubuntu-postgres
└── claude-db-project  (container) → mounts .../db-project/
```

**The key principle:** build common tools into the base image once. Add project-specific tools in thin layers on top. Your code and Claude config always live on your host disk — never inside the container.

---

## Prerequisites

- **Podman** installed on your Linux system
- A decision on where your projects will live

> **Note:** Node.js is no longer required to install Claude Code. The official native installer (`curl -fsSL https://claude.ai/install.sh | bash`) handles everything. Node.js is only needed if your projects themselves use it.

### Know your host system — SELinux and volume mounts

This guide uses volume mount options (the `:Z` flag) that behave differently depending on your Linux distribution. Before proceeding, check whether your system uses SELinux:

```bash
getenforce
```

| Output | Meaning |
|---|---|
| `Enforcing` | SELinux is active and enforcing policies — `:Z` is required |
| `Permissive` | SELinux is active but not blocking — `:Z` is safe but not strictly needed |
| `Disabled` | SELinux is not running — `:Z` is harmless but unnecessary |
| `command not found` | SELinux is not installed on this system |

**Fedora / RHEL / CentOS** run SELinux in `Enforcing` mode by default. Without `:Z` on volume mounts, the container process will be blocked from accessing the mounted directories even if the Unix file permissions look correct. The error typically appears as `Permission denied` inside the container with no obvious cause.

**Ubuntu / Debian / Arch** do not use SELinux by default. They use AppArmor or no MAC system at all. The `:Z` flag is accepted by Podman on these systems but has no effect — you can leave it in place or remove it.

> **Reference system used in this guide:** Fedora with SELinux in `Enforcing` mode, an NVMe SSD (encrypted with LUKS) for the OS and home directory, and a second HDD mounted at `/mnt/data` for project storage. All examples and paths reflect this setup — adapt them to your own system as needed.

The `:Z` flag tells Podman to relabel the mounted directory with an SELinux context that the container process is allowed to access. There is also a lowercase `:z` variant — the difference is:

- `:Z` — private label, accessible by **only this container**
- `:z` — shared label, accessible by **multiple containers**

For per-project sandboxes where each directory belongs to one container, `:Z` is the correct choice.

### Where to put your projects

You need to choose a base directory. Common options:

| Option | When to use |
|---|---|
| `~/claude_projects/` | Single disk system, or everything on your main drive |
| `/mnt/data/claude_projects/` | Dedicated data partition or second disk |

Throughout this guide, this path is referred to as `$CLAUDE_SANDBOX_BASE`. Replace it with your actual path everywhere.

---

## Step 1 — Create the Directory Structure

```bash
# Set this to your chosen base path
CLAUDE_SANDBOX_BASE="/mnt/data/claude_projects"   # or ~/claude_projects

# Create the base directory
mkdir -p "$CLAUDE_SANDBOX_BASE"

# Create the directory for your Containerfiles
mkdir -p ~/.config/claude-sandbox
```

You do not need to create per-project directories now. A script will handle that later.

---

## Step 2 — Build the Base Image

The base image is built once and shared by all projects. It contains everything that is common across projects.

Save the following as `~/.config/claude-sandbox/Containerfile.base`:

```dockerfile
FROM ubuntu:24.04
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# Base tools
RUN apt-get update && apt-get install -y \
        git \
        curl \
        ca-certificates \
        sudo \
        bash-completion \
        vim \
        tmux \
        jq \
        unzip \
        xz-utils \
        bc \
        lsof \
        iproute2 \
        rsync \
        direnv \
        entr \
        rlwrap \
        psmisc \
        ripgrep \
        fd-find \
        kitty-terminfo \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# Node.js (LTS) — optional, only needed if your projects use Node.js
# Remove this block if you do not need Node.js in your projects
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# uv — fast Python package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh \
    && mv /root/.local/bin/uv /root/.local/bin/uvx /usr/local/bin/

# Python — managed by uv, available system-wide
# uv installs Python independently from the OS, giving you a clean,
# version-managed Python that doesn't conflict with system packages.
# To install a different version, change 3.12 to your preferred version.
RUN uv python install 3.12
RUN PYTHON_BIN=$(uv python find 3.12) \
    && ln -sf "$PYTHON_BIN" /usr/local/bin/python3 \
    && ln -sf "$PYTHON_BIN" /usr/local/bin/python

# Rust
RUN curl -LsSf https://sh.rustup.rs | sh -s -- -y --no-modify-path \
    && mv /root/.cargo/bin/* /usr/local/bin/

# Claude Code — installed as root into /usr/local/bin
# The native installer places the binary in $HOME/.local/share/claude/versions/
# and creates a symlink at $HOME/.local/bin/claude pointing to it.
# We redirect HOME to a temp directory, move the entire data directory to
# /usr/local/share/claude, then create a symlink in /usr/local/bin so claude
# remains accessible after the home volume mount at runtime.
# Docs: https://code.claude.com/docs/en/setup
RUN HOME=/tmp/claude-install \
    && mkdir -p $HOME \
    && curl -fsSL https://claude.ai/install.sh | bash \
    && mv /tmp/claude-install/.local/share/claude /usr/local/share/claude \
    && ln -sf /usr/local/share/claude/versions/$(ls /usr/local/share/claude/versions/) /usr/local/bin/claude \
    && rm -rf /tmp/claude-install

# User setup — rename default 'ubuntu' user to 'bb'
RUN usermod -l bb -d /home/bb -m ubuntu \
    && groupmod -n bb ubuntu \
    && echo "bb ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/bb \
    && chmod 440 /etc/sudoers.d/bb

USER bb
WORKDIR /home/bb
```

Build the base image:

```bash
podman build -t claude-ubuntu -f ~/.config/claude-sandbox/Containerfile.base
```

> **Note:** This build will take several minutes the first time. Subsequent builds are faster because Podman caches each layer. Only layers after a changed line are rebuilt.

---

## Step 3 — Creating Project-Specific Images

When a project needs tools or ports beyond the base image, you create an extended image that builds on top of `claude-ubuntu`.

### Creating an extended image

Save a new Containerfile as `~/.config/claude-sandbox/Containerfile.<suffix>`:

```dockerfile
FROM claude-ubuntu    # ← builds on your base, not ubuntu:24.04

# Add only what this project type needs
RUN sudo apt-get update && sudo apt-get install -y \
        postgresql-client \
    && sudo rm -rf /var/lib/apt/lists/*
```

Build it with a name following the `claude-ubuntu-<suffix>` convention:

```bash
podman build -t claude-ubuntu-postgres -f ~/.config/claude-sandbox/Containerfile.postgres
```

### Naming convention

Image names must follow this pattern for automatic detection to work:

```
claude-ubuntu             ← base image (always exists)
claude-ubuntu-postgres    ← extended image for projects needing postgres tools
claude-ubuntu-python      ← extended image for heavy Python projects
claude-ubuntu-webdev      ← extended image for web development
```

The `start-claude` script (Step 4) automatically selects the right image for each project based on this naming convention.

### Keeping extended images thin

Extended images should only contain what the base image does not. Since they inherit everything from `claude-ubuntu`, you do not need to reinstall git, curl, Claude Code, or any other base tool. A typical extended Containerfile is just a few lines.

---

## Step 4 — Install the Scripts

### Script 1: `new-claude-project`

This script creates a new project directory structure.

Save as `~/.local/bin/new-claude-project`:

```bash
#!/bin/bash
set -e

CLAUDE_SANDBOX_BASE="/mnt/data/claude_projects"   # ← change this to your base path

if [ -z "$1" ]; then
    echo "Usage: new-claude-project <project-name> [image-suffix]"
    echo ""
    echo "Examples:"
    echo "  new-claude-project my-app              # uses base image (claude-ubuntu)"
    echo "  new-claude-project my-app postgres     # uses claude-ubuntu-postgres"
    exit 1
fi

PROJECT="$1"
IMAGE_SUFFIX="${2:-}"
PROJECT_DIR="$CLAUDE_SANDBOX_BASE/$PROJECT"

if [ -d "$PROJECT_DIR" ]; then
    echo "Project '$PROJECT' already exists at $PROJECT_DIR"
    exit 1
fi

mkdir -p "$PROJECT_DIR/dev"
mkdir -p "$PROJECT_DIR/container"

# Write sandbox.conf
# Currently stores image suffix hint, but lines are commented out by default.
# Uncomment to migrate to explicit config (Option C).
cat > "$PROJECT_DIR/sandbox.conf" << EOF
# Claude sandbox configuration for project: $PROJECT
# This file is optional — if absent, the base image (claude-ubuntu) is used.
# To use explicit config instead of convention-based detection,
# uncomment and edit the lines below.

# IMAGE_SUFFIX=$IMAGE_SUFFIX
# EXTRA_PORTS=
EOF

echo "Created project: $PROJECT"
echo "  Code dir:       $PROJECT_DIR/dev"
echo "  Container home: $PROJECT_DIR/container"
echo "  Config file:    $PROJECT_DIR/sandbox.conf"
if [ -n "$IMAGE_SUFFIX" ]; then
    echo "  Suggested image: claude-ubuntu-$IMAGE_SUFFIX"
    echo "  (create it with: podman build -t claude-ubuntu-$IMAGE_SUFFIX -f ~/.config/claude-sandbox/Containerfile.$IMAGE_SUFFIX)"
else
    echo "  Image: claude-ubuntu (base)"
fi
echo ""
echo "Start it with: start-claude $PROJECT"
```

Make it executable:

```bash
chmod +x ~/.local/bin/new-claude-project
```

### Script 2: `start-claude`

This script starts a container for a specific project, automatically selecting the right image.

**Image selection logic:**
1. Check if `sandbox.conf` has `IMAGE_SUFFIX` uncommented — use that image (explicit config)
2. Otherwise, check if an image named `claude-ubuntu-<project>` exists — use it if found (convention)
3. Otherwise, fall back to `claude-ubuntu` (base image)

Save as `~/.local/bin/start-claude`:

```bash
#!/bin/bash
set -e

CLAUDE_SANDBOX_BASE="/mnt/data/claude_projects"   # ← change this to your base path
BASE_IMAGE="claude-ubuntu"

if [ -z "$1" ]; then
    echo "Usage: start-claude <project-name>"
    echo ""
    echo "Available projects:"
    ls "$CLAUDE_SANDBOX_BASE"
    exit 1
fi

PROJECT="$1"
PROJECT_DIR="$CLAUDE_SANDBOX_BASE/$PROJECT"
CONTAINER_NAME="claude-$PROJECT"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Project '$PROJECT' not found. Create it first with:"
    echo "  new-claude-project $PROJECT"
    exit 1
fi

# ── Image selection ──────────────────────────────────────────────────────────
#
# Priority:
#   1. sandbox.conf with IMAGE_SUFFIX uncommented  (explicit config)
#   2. Image named claude-ubuntu-<project> exists  (convention-based)
#   3. Base image claude-ubuntu                    (fallback)

IMAGE="$BASE_IMAGE"
CONF_FILE="$PROJECT_DIR/sandbox.conf"

# Check sandbox.conf first (explicit config)
if [ -f "$CONF_FILE" ]; then
    CONF_SUFFIX=$(grep -E "^IMAGE_SUFFIX=" "$CONF_FILE" | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$CONF_SUFFIX" ]; then
        IMAGE="${BASE_IMAGE}-${CONF_SUFFIX}"
        echo "Using image from sandbox.conf: $IMAGE"
    fi
fi

# If no config override, try convention-based name
if [ "$IMAGE" = "$BASE_IMAGE" ]; then
    CONVENTION_IMAGE="${BASE_IMAGE}-${PROJECT}"
    if podman image exists "$CONVENTION_IMAGE" 2>/dev/null; then
        IMAGE="$CONVENTION_IMAGE"
        echo "Using project image: $IMAGE"
    fi
fi

# Confirm the selected image actually exists
if ! podman image exists "$IMAGE" 2>/dev/null; then
    echo "Error: image '$IMAGE' not found."
    echo "Available claude images:"
    podman images --filter "reference=claude-ubuntu*" --format "{{.Repository}}"
    exit 1
fi

echo "Project:   $PROJECT"
echo "Image:     $IMAGE"
echo "Container: $CONTAINER_NAME"
echo ""

# ── Port configuration ───────────────────────────────────────────────────────
#
# Default ports exposed for all containers.
# To add project-specific ports, uncomment EXTRA_PORTS in sandbox.conf.

DEFAULT_PORTS="-p 3000:3000 -p 4000:4000 -p 5173:5173 -p 8000:8000 -p 8080:8080"

EXTRA_PORTS=""
if [ -f "$CONF_FILE" ]; then
    CONF_PORTS=$(grep -E "^EXTRA_PORTS=" "$CONF_FILE" | cut -d= -f2 | tr -d '[:space:]')
    if [ -n "$CONF_PORTS" ]; then
        for port in $CONF_PORTS; do
            EXTRA_PORTS="$EXTRA_PORTS -p ${port}:${port}"
        done
    fi
fi

# ── Start container ──────────────────────────────────────────────────────────
#
# Three possible states:
#   1. Running   → do nothing, just exec into it
#   2. Stopped   → podman start (reuse existing container)
#   3. Missing   → podman run (create new container)

if podman ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container already running."
elif podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Resuming stopped container..."
    podman start "$CONTAINER_NAME" > /dev/null
else
    echo "Starting container..."
    podman run -d \
        --name "$CONTAINER_NAME" \
        --init \
        --userns=keep-id \
        --security-opt label=disable \
        $DEFAULT_PORTS \
        $EXTRA_PORTS \
        -v "$PROJECT_DIR/container:/home/bb:Z" \
        -v "$PROJECT_DIR/dev:/home/bb/dev:Z" \
        --pids-limit 4096 \
        --cpus 4 \
        --memory 8g \
        -w /home/bb/dev \
        "$IMAGE" \
        tail -f /dev/null
    echo "Container started."
fi

podman exec -it \
    -w "/home/bb/dev" \
    "$CONTAINER_NAME" \
    bash -lc "export PATH=\"\$HOME/.local/bin:\$PATH\" && claude --dangerously-skip-permissions"
    # Note: claude lives in /usr/local/bin (always on PATH).
    # The ~/.local/bin export is kept for any tools Claude Code installs at runtime.
```

Make it executable:

```bash
chmod +x ~/.local/bin/start-claude
```

### Script 3: `stop-claude`

Save as `~/.local/bin/stop-claude`:

```bash
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: stop-claude <project-name>"
    echo ""
    echo "Running Claude containers:"
    podman ps --filter "name=claude-" --format "{{.Names}}"
    exit 1
fi

CONTAINER_NAME="claude-$1"
podman stop "$CONTAINER_NAME" && echo "Stopped: $CONTAINER_NAME"
```

Make it executable:

```bash
chmod +x ~/.local/bin/stop-claude
```

### Ensure `~/.local/bin` is on your PATH

Check if it is already:

```bash
echo $PATH | grep -q "$HOME/.local/bin" && echo "Already on PATH" || echo "Not on PATH"
```

If not, add this line to your `~/.bashrc` (or `~/.zshrc` if using Zsh):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload:

```bash
source ~/.bashrc
```

### Tab completion for project names (optional)

To enable tab completion so that pressing Tab after `start-claude`, `stop-claude`, or `new-claude-project` auto-completes project names from your sandbox base directory:

```bash
mkdir -p ~/.local/share/bash-completion/completions

cat > ~/.local/share/bash-completion/completions/claude-sandbox << 'EOF'
_claude_projects() {
    local CLAUDE_SANDBOX_BASE="/mnt/data/claude_projects"   # ← change to your base path
    local projects=$(ls "$CLAUDE_SANDBOX_BASE" 2>/dev/null)
    COMPREPLY=($(compgen -W "$projects" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _claude_projects start-claude
complete -F _claude_projects stop-claude
complete -F _claude_projects new-claude-project
EOF
```

Then reload your shell:

```bash
source ~/.bashrc
```

If tab completion doesn't work after reloading, source the completion file manually and make it permanent. The cleanest approach depends on your distro:

**Option A — `~/.bashrc.d/` (Fedora, Ubuntu 22.04+, Debian 12+)**

Many modern distros auto-load any file placed in `~/.bashrc.d/`. This keeps `.bashrc` clean:

```bash
mkdir -p ~/.bashrc.d
echo 'source ~/.local/share/bash-completion/completions/claude-sandbox' > ~/.bashrc.d/claude-sandbox
source ~/.bashrc
```

**Option B — Add directly to `~/.bashrc` (any distro)**

If your distro doesn't have `~/.bashrc.d/`, append directly to `.bashrc`:

```bash
echo 'source ~/.local/share/bash-completion/completions/claude-sandbox' >> ~/.bashrc
source ~/.bashrc
```

> **Reference system (Fedora):** bash-completion loads from `/etc/profile.d/bash_completion.sh` for login shells only. New terminal windows (interactive non-login shells) don't auto-scan `~/.local/share/bash-completion/completions/`, so the explicit source line is required. Option A is used on this system — the completion file lives at `~/.bashrc.d/claude-sandbox`.

Verify it's registered correctly:

```bash
complete -p start-claude
```

Should return `complete -F _claude_projects start-claude`.

Test it by typing `start-claude ` and pressing Tab — it should list your projects.

> **Note:** If you change `CLAUDE_SANDBOX_BASE` in your scripts, update it in the completion file too — it reads the same directory independently.

### Create a new project (base image)

```bash
new-claude-project my-app
```

### Create a new project with a specific image

```bash
new-claude-project my-app postgres
# → will use claude-ubuntu-postgres if it exists
```

### Start Claude Code in a project

```bash
start-claude my-app
```

This will:
1. Read `sandbox.conf` to check for an explicit image override
2. If no override, check if `claude-ubuntu-my-app` exists
3. Fall back to `claude-ubuntu` if neither applies
4. Start the container and drop you into Claude Code

### Stop the container when done

```bash
stop-claude my-app
```

### List running Claude containers

```bash
podman ps --filter "name=claude-"
```

### List all Claude containers including stopped

```bash
podman ps -a --filter "name=claude-"
```

---

## Step 6 — Migrating to Explicit Config

As your projects grow, you may want each project's configuration to be explicit and self-documenting rather than relying on naming conventions.

Every project already has a `sandbox.conf` created by `new-claude-project`. To switch a project to explicit config, simply uncomment the relevant lines:

```bash
# $CLAUDE_SANDBOX_BASE/my-app/sandbox.conf

IMAGE_SUFFIX=postgres     # ← uncommented: now uses claude-ubuntu-postgres explicitly
EXTRA_PORTS=5432 9000     # ← uncommented: adds these ports on top of defaults
```

The `start-claude` script checks `sandbox.conf` first, so once you uncomment `IMAGE_SUFFIX` it takes priority over the convention-based detection. You can migrate projects one at a time — projects without an uncommented `IMAGE_SUFFIX` continue using convention-based detection.

---

## The Image Rebuild Cycle

Understanding when and how to rebuild the image is important. This is a recurring operation any time you change your toolset.

### The full cycle explained

There are three distinct layers and each has its own update process:

```
Containerfile  →  Image  →  Container
(your recipe)     (built)    (running instance)
```

- Changing the **Containerfile** does nothing on its own — it's just a text file
- **Building** the image bakes the Containerfile into a new image snapshot
- **Recreating** the container applies the new image — existing containers keep using the old image until recreated

### When you need to rebuild

| What changed | Rebuild image? | Recreate container? |
|---|---|---|
| Containerfile (added/removed tool) | ✅ Yes | ✅ Yes |
| `start-claude` script (changed ports or flags) | ❌ No | ✅ Yes |
| `sandbox.conf` (changed image or ports for one project) | ❌ No | ✅ Yes |
| Code in `dev/` | ❌ No | ❌ No |
| Claude config in `container/` | ❌ No | ❌ No |

### The exact commands in order

**When you change the base Containerfile:**

```bash
# 1. Rebuild the base image
podman build -t claude-ubuntu -f ~/.config/claude-sandbox/Containerfile.base

# 2. Stop the affected container
stop-claude <project-name>

# 3. Delete the container (so it gets recreated with the new image)
podman rm claude-<project-name>

# 4. Start fresh — picks up the new image automatically
start-claude <project-name>
```

**When you change an extended Containerfile:**

```bash
# 1. Rebuild only the extended image (base image is unchanged)
podman build -t claude-ubuntu-<suffix> -f ~/.config/claude-sandbox/Containerfile.<suffix>

# 2-4. Same stop → rm → start as above
```

**When you only change `start-claude` or `sandbox.conf` (no Containerfile change):**

```bash
# No rebuild needed — just recreate the container
stop-claude <project-name>
podman rm claude-<project-name>
start-claude <project-name>
```

### Why existing containers are not affected by a rebuild

This is a deliberate design of container systems. When a container is created with `podman run`, it takes a snapshot reference to the image at that moment. Rebuilding the image creates a new snapshot — but existing containers still point to the old one. This protects running containers from unexpected changes mid-session.

The `podman rm` step is what breaks that reference and forces the next `start-claude` to use the current image.

### Your code and config are always safe

Recreating a container does not touch your mounted volumes. Everything in `$CLAUDE_SANDBOX_BASE/<project>/dev/` and `$CLAUDE_SANDBOX_BASE/<project>/container/` lives on your host disk and is completely unaffected by container deletion and recreation.

---

## Managing Tools — Adding and Removing

### Adding a tool to the base image

Edit `~/.config/claude-sandbox/Containerfile.base`, add the tool, then rebuild:

```bash
podman build -t claude-ubuntu -f ~/.config/claude-sandbox/Containerfile.base
```

### Adding a tool to an extended image

Edit `~/.config/claude-sandbox/Containerfile.<suffix>` and rebuild:

```bash
podman build -t claude-ubuntu-postgres -f ~/.config/claude-sandbox/Containerfile.postgres
```

### Recreating containers after a rebuild

Rebuilding the image does not affect running containers — they continue using the old image until recreated. To apply the new image:

```bash
stop-claude my-app
podman rm claude-my-app
start-claude my-app      # starts fresh with the new image
```

Your code and Claude config are safe — they live in your mounted volumes, not inside the container.

### Adding a port to all projects

Edit the `DEFAULT_PORTS` line in `start-claude`, then recreate any running containers.

### Adding a port to one project only

Uncomment and edit `EXTRA_PORTS` in that project's `sandbox.conf`:

```bash
EXTRA_PORTS=5432 9000
```

Then recreate the container:

```bash
stop-claude my-app
podman rm claude-my-app
start-claude my-app
```

> **Why can't you add ports to a running container?** Ports are configured at container creation time. This is a fundamental limitation of how container networking works — you must recreate the container to change port mappings.

---

## Understanding Persistence

| What | Where it lives | Persists after container stop? |
|---|---|---|
| Your code | `$CLAUDE_SANDBOX_BASE/<project>/dev/` | ✅ Yes — on your host disk |
| Claude config and context | `$CLAUDE_SANDBOX_BASE/<project>/container/` | ✅ Yes — on your host disk |
| CLAUDE.md | `$CLAUDE_SANDBOX_BASE/<project>/container/` | ✅ Yes |
| sandbox.conf | `$CLAUDE_SANDBOX_BASE/<project>/` | ✅ Yes |
| Packages installed manually inside container | Inside the container layer | ❌ No — lost on container delete |
| Tools installed in the image | The image itself | ✅ Yes — survives restarts, lost only if image is rebuilt |

**Key principle:** Anything important must live in a mounted volume. The container itself is disposable — the image and your mounted directories are what matter.

---

## What Each Tool in the Base Image Does

| Tool | Purpose |
|---|---|
| `git` | Version control — essential for any project |
| `curl` | HTTP requests from the command line — used by installers and Claude Code |
| `ca-certificates` | SSL certificate authorities — required for HTTPS to work |
| `sudo` | Run commands as root from within the container |
| `bash-completion` | Tab completion for bash commands |
| `vim` | Terminal text editor |
| `tmux` | Terminal multiplexer — run multiple terminals in one session |
| `jq` | Parse and manipulate JSON from the command line |
| `unzip` / `xz-utils` | Extract archives |
| `bc` | Command-line calculator |
| `lsof` | List open files and network connections — useful for debugging |
| `iproute2` | Network tools (`ip` command) |
| `rsync` | Efficient file sync and copy |
| `direnv` | Automatically load/unload environment variables per directory |
| `entr` | Re-run commands when files change — useful for dev watch loops |
| `rlwrap` | Adds history and arrow key support to REPLs |
| `psmisc` | Process tools (`killall`, `pstree`) |
| `ripgrep` | Fast file content search — used heavily by Claude Code |
| `fd-find` | Fast file finder — alternative to `find` |
| `kitty-terminfo` | Terminal compatibility for the Kitty terminal emulator |
| `Node.js` | JavaScript runtime — optional, only needed if your projects use it (Claude Code no longer depends on it) |
| `uv` | Fast Python package and project manager |
| `Python 3.12` | Installed and managed by uv — clean, version-managed, does not conflict with OS packages |
| `build-essential` | GCC compiler, make, and C standard library headers — required for compiling Rust projects and any C/C++ dependencies |
| `Rust` | Systems programming language and its toolchain (`cargo`, `rustc`) |

---

## Quick Reference

```bash
# Create a new project (base image)
new-claude-project <project-name>

# Create a new project with extended image
new-claude-project <project-name> <image-suffix>

# Start Claude Code in a project
start-claude <project-name>

# Stop a project's container
stop-claude <project-name>

# List running containers
podman ps --filter "name=claude-"

# List all containers including stopped
podman ps -a --filter "name=claude-"

# Rebuild the base image
podman build -t claude-ubuntu -f ~/.config/claude-sandbox/Containerfile.base

# Rebuild an extended image
podman build -t claude-ubuntu-<suffix> -f ~/.config/claude-sandbox/Containerfile.<suffix>

# Delete a container (to recreate with new image)
podman rm claude-<project-name>

# List all claude images
podman images --filter "reference=claude-ubuntu*"

# Remove unused images
podman image prune
```
