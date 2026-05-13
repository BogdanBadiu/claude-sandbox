# Security Policy

## Supported Versions

Only the latest release is supported with security fixes.

## Reporting a Vulnerability

Please do **not** open a public issue for security vulnerabilities.

Use GitHub's private vulnerability reporting instead:
**[Report a vulnerability](https://github.com/BogdanBadiu/claude-sandbox/security/advisories/new)**

Include:
- A description of the vulnerability
- Steps to reproduce it
- The potential impact

You will receive a response within 7 days. If the issue is confirmed, a fix will be released as soon as possible and you will be credited in the release notes (unless you prefer to remain anonymous).

## Scope

This tool manages Podman containers on your local machine. The main security considerations are:

- **Filesystem isolation** — each container only has access to its own `dev/` and `container/` directories
- **Rootless containers** — Podman runs without root; a container escape lands in your user account, not root
- **No credential sharing** — host SSH keys and tokens are not mounted into containers
- **`--dangerously-skip-permissions`** — this flag is intentional and safe within the container isolation model; see the README for full context
