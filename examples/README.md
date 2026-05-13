# Example Containerfiles

Ready-to-use extended images for common project types. Each one builds on top of
the `claude-ubuntu` base image — so Claude Code, Node.js, Python, Rust, and uv
are already included.

## How to use

1. Copy the Containerfile to `~/.config/claude-sandbox/` (or link it):

```bash
# Option A — copy
cp examples/Containerfile.postgres ~/.config/claude-sandbox/

# Option B — link (changes to the source file are picked up at build time)
claude-sandbox link containerfile postgres ~/path/to/claude-sandbox/examples/Containerfile.postgres
```

2. Build the image:

```bash
claude-sandbox build postgres
```

3. Create a project that uses it:

```bash
claude-sandbox new my-app postgres
```

The suffix (`postgres`, `go`, `java`, `codex`) is the same string in all three steps.

## Available examples

| File | Image built | What's added |
|---|---|---|
| `Containerfile.postgres` | `claude-ubuntu-postgres` | PostgreSQL server + client |
| `Containerfile.go` | `claude-ubuntu-go` | Go toolchain (latest stable) |
| `Containerfile.java` | `claude-ubuntu-java` | OpenJDK 21 LTS + Maven |
| `Containerfile.codex` | `claude-ubuntu-codex` | Codex CLI (OpenAI — cloud) |
| `Containerfile.aider` | `claude-ubuntu-aider` | Aider with Ollama (local models) |

## Running a different AI agent

By default `claude-sandbox start` runs Claude Code. To run a different agent,
set `AGENT_CMD` (and optionally `AGENT_ARGS`) in the project's `sandbox.conf`:

```bash
# sandbox.conf for a Codex project
IMAGE_SUFFIX=codex
AGENT_CMD=codex
AGENT_ARGS=--full-auto
```

**How `SKIP_PERMISSIONS` interacts with other agents:**
`--dangerously-skip-permissions` is a Claude Code flag. It is only appended
automatically when `AGENT_CMD=claude` (or absent). For other agents, put the
equivalent unattended flag directly in `AGENT_ARGS` and leave `SKIP_PERMISSIONS`
as-is — it will be ignored.

## Local models with Aider + Ollama

Aider is a popular open-source coding assistant that works with local models via
Ollama — no cloud API key required. The architecture keeps Ollama on your host
(where your GPU is) and runs Aider inside the container.

**Prerequisites on your host:**

```bash
# Install Ollama (https://ollama.com) then pull a coding model
ollama pull qwen2.5-coder:32b    # recommended — strong coding, fits in ~20 GB VRAM
ollama pull deepseek-coder-v2    # good alternative
ollama pull codellama            # lighter option for smaller GPUs
```

**Build and create the project:**

```bash
claude-sandbox link containerfile aider ~/path/to/claude-sandbox/examples/Containerfile.aider
claude-sandbox build aider
claude-sandbox new my-app aider
```

**Edit `sandbox.conf`:**

```bash
IMAGE_SUFFIX=aider
AGENT_CMD=aider
AGENT_ARGS=--model ollama/qwen2.5-coder:32b --no-auto-commits
```

**Start:**

```bash
claude-sandbox start my-app
```

Aider connects to Ollama on your host via `host.containers.internal:11434` —
this is set automatically in the image. To switch models, just change the model
name in `AGENT_ARGS` and restart — no rebuild needed.

## Reducing image size by removing Claude Code

Claude Code is installed in `claude-ubuntu` and is present in every extended
image. If you are building an image for a project that will never use Claude Code,
you can remove it to save ~200-300 MB. Add this line to your Containerfile:

```dockerfile
FROM claude-ubuntu

# Remove Claude Code to reduce image size
RUN sudo rm -rf /usr/local/share/claude /usr/local/bin/claude

# ... rest of your Containerfile
```

Only do this if you are certain — you cannot undo it without rebuilding the image.
The `Containerfile.codex` example has this line commented out as a reference.

## Writing your own

Start from this template:

```dockerfile
FROM claude-ubuntu

RUN sudo apt-get update && sudo apt-get install -y \
        <your-packages> \
    && sudo rm -rf /var/lib/apt/lists/*
```

Key rules:
- Always `FROM claude-ubuntu` — never `FROM ubuntu` directly
- Use `sudo apt-get` — the container user (`sandbox`) is not root
- Clean up apt lists in the same `RUN` layer to keep the image small
- Name the file `Containerfile.<suffix>` — the suffix becomes the image name suffix
