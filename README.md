# claude-sandbox

A CLI tool that sets up and manages isolated, per-project Claude Code sandboxes using Podman and Ubuntu containers. Each project gets its own container with its own Claude context, code directory, and persistent home — with no access to the rest of your host filesystem.

---

## Why sandboxes?

Running Claude Code directly on your machine means it can read and modify any file your user account can access. A sandbox changes that:

- **Filesystem isolation** — Claude can only see what is mounted into the container: your project's `dev/` directory and nothing else. Your home directory, other projects, and system files are invisible to it.
- **Per-project Claude context** — each project has its own Claude conversation history, memory, and `CLAUDE.md` instructions. Claude working on `project-a` has no knowledge of `project-b`.
- **No credential leakage** — your host SSH keys, tokens, and config files are not shared into containers. Each project gets its own deploy key with access only to the repositories you explicitly grant.
- **Parallel agents** — you can run multiple projects simultaneously. Each container is fully independent, so Claude can work on one branch while you work on another with no interference.
- **Rootless by design** — Podman runs containers without root privileges. A container escape would land in your user account, not root.
- **Persistent across restarts** — the container's home directory is a regular folder on your disk. Stop and start a project as many times as you want — Claude's context, installed tools, and configuration survive.

The manual setup guide in `docs/manual-setup.md` describes everything the tool does under the hood, if you want to understand the details.

---

## Requirements

- Linux (Fedora, RHEL, Ubuntu, Debian, Arch, openSUSE, or Alpine)
- [Podman](https://podman.io/) (installed automatically by `claude-sandbox init` if missing)
- No root or sudo required for normal operation — Podman rootless is the whole point

---

## Installation

```bash
# Clone the repository and run the installer
git clone https://github.com/BogdanBadiu/claude-sandbox.git
cd claude-sandbox
bash install.sh
```

Or install directly with curl (once the repository is published):

```bash
curl -fsSL https://raw.githubusercontent.com/BogdanBadiu/claude-sandbox/main/install.sh | bash
```

Both methods install the binary to `~/.local/bin/claude-sandbox` and add it to your `PATH` in `~/.bashrc` / `~/.zshrc` automatically. Apply the change in your current shell session:

```bash
source ~/.bashrc   # or: source ~/.zshrc
```

Then run `claude-sandbox init` to complete setup.

---

## Quick Start

```bash
# First-time setup (installs Podman if needed, builds base image)
claude-sandbox init
```

During `init`, you will be prompted for a **projects directory**:

```
Projects directory [~/claude_projects]:
```

This is the single location where all your project sandboxes will be stored. Every project
you create with `claude-sandbox new` gets its own subdirectory here — containing the code,
Claude's persistent home, and per-project config. You choose this location once during `init`
and it is saved to `~/.config/claude-sandbox/config`.

- Press Enter to accept the default (`~/claude_projects` under your home directory)
- Or type a custom path, for example `/mnt/data/claude_projects` if you have a separate disk
  with more space (useful if you plan to run many projects with large codebases)

```bash
# Create a new project
claude-sandbox new my-app

# Start Claude Code in the project (creates container on first run)
claude-sandbox start my-app

# Stop the container when done
claude-sandbox stop my-app

# Resume where you left off
claude-sandbox start my-app
```

---

## Flags

| Flag | Description |
|---|---|
| `--debug` | Print DEBUG log messages to stderr in addition to the log file |

```bash
claude-sandbox --debug start my-app
```

---

## Subcommands

| Command | Description |
|---|---|
| `claude-sandbox init` | First-time setup: installs dependencies, builds base image |
| `claude-sandbox new <project>` | Create a new project sandbox |
| `claude-sandbox new <project> <image>` | Create with a specific extended image |
| `claude-sandbox new <project> --safe` | Create with permission prompts enabled |
| `claude-sandbox start <project>` | Start or resume a project (creates container if needed) |
| `claude-sandbox shell <project>` | Open a plain shell in the project container |
| `claude-sandbox stop <project>` | Stop a running project's container |
| `claude-sandbox list` | List all projects and their container status |
| `claude-sandbox build` | Rebuild the base image (`claude-ubuntu`) |
| `claude-sandbox build <suffix>` | Rebuild a specific extended image |
| `claude-sandbox remove <project>` | Remove a project and its container (with confirmation) |
| `claude-sandbox logs [--lines <n>]` | Print last N lines of the log file (default 50) |
| `claude-sandbox claude-md <project>` | Create or edit the project's CLAUDE.md in `$EDITOR` |
| `claude-sandbox claude-md <project> <path>` | Install a CLAUDE.md from an existing file |
| `claude-sandbox link git <project>` | Generate a per-project SSH deploy key for git access |
| `claude-sandbox link containerfile <suffix> <path>` | Register a Containerfile from any path |
| `claude-sandbox uninstall` | Remove claude-sandbox (keeps projects directory by default) |
| `claude-sandbox uninstall --remove-projects` | Also delete the projects directory and all project data |
| `claude-sandbox status` | Show tool configuration and system info |
| `claude-sandbox help` | Show usage |

---

## Project Directory Structure

All projects live under `CLAUDE_SANDBOX_BASE` (configured during `init`):

```
$CLAUDE_SANDBOX_BASE/
├── my-app/
│   ├── dev/          ← your code — mounted as /home/sandbox/dev inside the container
│   ├── container/    ← container's home — Claude config, context, CLAUDE.md
│   └── sandbox.conf  ← per-project config
```

Your code and Claude configuration live on your host disk and survive container deletion.

The container user is always `sandbox`, independent of your host machine username. The home directory inside every container is `/home/sandbox`.

---

## sandbox.conf

Each project has a `sandbox.conf` created by `claude-sandbox new`. Comment lines are ignored.

```bash
# Claude sandbox configuration for project: my-app
# Uncomment and edit to override defaults.

# IMAGE_SUFFIX=          # use claude-ubuntu-<suffix> instead of base image
# EXTRA_PORTS=           # space-separated ports to expose in addition to defaults
SKIP_PERMISSIONS=true    # set to false to enable Claude Code permission prompts
```

Default ports exposed on every container: `3000`, `4000`, `5173`, `8000`, `8080`.

---

## Per-Project CLAUDE.md

Each project can have its own `CLAUDE.md` — the file Claude Code reads for project-specific
instructions, context, and constraints. This is the main reason to have separate projects:
each one gets its own isolated Claude context and behaviour.

```bash
# Create or edit a project's CLAUDE.md in your default editor
claude-sandbox claude-md my-app

# Install a CLAUDE.md from an existing file (e.g. a shared template)
claude-sandbox claude-md my-app ~/templates/backend-claude.md
```

The file is placed at `<projects-dir>/my-app/dev/CLAUDE.md`, which maps to
`~/dev/CLAUDE.md` inside the container — exactly where Claude Code looks first.

If no `CLAUDE.md` exists yet, the first command creates a starter template and opens it
in `$EDITOR`. If one already exists, it opens it directly. The second form asks for
confirmation before overwriting.

---

## Accessing the Container Directly

`claude-sandbox start` launches Claude Code inside the container. If you want a plain shell instead — to inspect files, run commands manually, test a running app, or debug — use `shell`:

```bash
claude-sandbox shell my-app
```

This starts the container if it is not running (same lifecycle as `start`), then drops you into a `bash` session as the `sandbox` user in the project's `dev/` directory. You can run any command, check ports, inspect processes, or test your application directly.

To use Claude Code and a shell at the same time, open two separate terminals:

```
# Terminal 1
claude-sandbox start my-app    ← Claude Code runs here

# Terminal 2
claude-sandbox shell my-app    ← your shell in the same container
```

Both connect to the same running container, so you can watch Claude Code build something in one terminal while testing it in the other.

When you are done, type `exit` or press `Ctrl+D` to leave the shell. The container keeps running until you explicitly stop it with `claude-sandbox stop my-app`.

---

## Git Access Inside Containers

Each container is isolated — your host SSH keys are not shared into containers by design. Use `link git` to give a project its own deploy key with access only to the repositories you choose.

```bash
# Generate a deploy key for a project
claude-sandbox link git my-app
```

The command prints the public key. To register it on GitHub:

1. Go to your repository on GitHub
2. Click **Settings** (the repo's settings tab, not your profile)
3. Left sidebar → **Security** → **Deploy keys**
4. Click **Add deploy key**, paste the public key, check **Allow write access** if Claude Code needs to push commits

Direct URL: `https://github.com/<you>/<your-repo>/settings/keys`

For GitLab: repository → **Settings** → **Repository** → **Deploy keys**.

The key is stored in `$CLAUDE_SANDBOX_BASE/my-app/container/.ssh/` and is available at `~/.ssh/` inside the container. Git is pre-configured to use it automatically for `github.com` and `gitlab.com` — no extra setup needed inside the container.

Running `link git` on a project that already has a key prints the existing key without regenerating it.

**Key scope:** each deploy key is tied to a specific repository (or repositories you add it to), not to your GitHub account. A key added to `my-app` cannot access `my-other-app`'s repo unless you explicitly add it there too.

**Multiple users, same repo:** GitHub allows any number of deploy keys per repository. If several people each run `claude-sandbox link git <project>` on their own machines, each gets a unique keypair. Each person adds their own public key to the same repo's deploy keys — GitHub lets you label them (e.g. "alice-sandbox", "bob-sandbox") so you can manage them independently.

---

## Extended Images

When a project needs tools beyond the base image, create an extended image.

**Option A — write the Containerfile directly** into the config directory:

```
# ~/.config/claude-sandbox/Containerfile.postgres
FROM claude-ubuntu

RUN sudo apt-get update && sudo apt-get install -y \
        postgresql-client \
    && sudo rm -rf /var/lib/apt/lists/*
```

**Option B — link an existing Containerfile** from anywhere on your filesystem:

```bash
claude-sandbox link containerfile postgres ~/my-project/Containerfile.postgres
```

This creates a symlink in `~/.config/claude-sandbox/` pointing to your file. The source
file can live anywhere — inside a project directory, a shared location, etc. Changes to
the source file are picked up the next time you build.

Either way, build the image:

```bash
claude-sandbox build postgres
```

Then create a project that uses it:

```bash
claude-sandbox new my-db-app postgres
```

Image selection order when starting a project:
1. `IMAGE_SUFFIX` in `sandbox.conf` (if uncommented)
2. `claude-ubuntu-<project-name>` if that image exists
3. `claude-ubuntu` base image (fallback)

---

## Logs

All subcommands write to a log file at `~/.local/share/claude-sandbox/claude-sandbox.log`.

```bash
# View the last 50 log lines
claude-sandbox logs

# View the last 100 lines
claude-sandbox logs --lines 100

# Stream DEBUG output to the terminal while running a command
claude-sandbox --debug start my-app
```

The log captures INFO, DEBUG, and ERROR messages for every operation. It is the first place to look when something goes wrong.

---

## Uninstalling

```bash
claude-sandbox uninstall                 # keeps your projects directory
claude-sandbox uninstall --remove-projects  # also deletes all project data
```

One confirmation prompt (`yes`), then everything is removed:
- All `claude-*` containers and `claude-ubuntu*` images (via Podman)
- Config: `~/.config/claude-sandbox/`
- Logs: `~/.local/share/claude-sandbox/`
- Shell completions
- The `claude-sandbox` binary itself

The projects directory (your code and Claude context) is **kept by default** — pass
`--remove-projects` only if you want to wipe it completely.

---

## Troubleshooting

**`Error: Containerfile not found: ~/.config/claude-sandbox/Containerfile.base`**
Run `claude-sandbox init` to create the base Containerfile. For extended images, create the file manually before running `claude-sandbox build <suffix>`.

**`Error: claude-sandbox is not initialized.`**
Run `claude-sandbox init` first.

**Permission denied inside container (Fedora/RHEL)**
Your system uses SELinux. The `:Z` volume mount flag handles this automatically — it is always included.

**Container starts but Claude Code is not found**
The base image installs Claude Code to `/usr/local/bin/claude` (not `~/.local/bin`) so it remains accessible after the home volume is mounted. If you are using a custom image, ensure it follows the same pattern.

**Port already in use**
Another container or process is using one of the default ports. Stop it, or add a project-specific port mapping via `EXTRA_PORTS` in `sandbox.conf`.

**`git push` fails inside the container**
The container does not have access to your host SSH keys. Run `claude-sandbox link git <project>` on the host, add the printed public key as a deploy key on your repository, then retry.
