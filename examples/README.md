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

The suffix (`postgres`, `go`, `java`) is the same string in all three steps.

## Available examples

| File | Image built | What's added |
|---|---|---|
| `Containerfile.postgres` | `claude-ubuntu-postgres` | PostgreSQL server + client |
| `Containerfile.go` | `claude-ubuntu-go` | Go toolchain (latest stable) |
| `Containerfile.java` | `claude-ubuntu-java` | OpenJDK 21 LTS + Maven |

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
