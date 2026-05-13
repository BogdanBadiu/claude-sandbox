# Contributing to claude-sandbox

Thanks for your interest in contributing. This is a small, focused tool — contributions that keep it simple and reliable are most welcome.

## Reporting bugs

Open an issue and include:
- Your Linux distribution and version
- Podman version (`podman --version`)
- The exact command you ran
- The error message or unexpected behaviour
- Relevant log output (`claude-sandbox logs --lines 50`)

## Suggesting features

Open an issue describing what you want to do and why the current tool does not support it. Keep in mind the project's goals: simplicity, no root required, per-project isolation.

## Submitting changes

1. Fork the repository and create a branch from `main`
2. Make your changes in `src/claude-sandbox`
3. Run the test suite and make sure all tests pass:
   ```bash
   make test
   ```
4. If you are adding a new subcommand or changing user-facing behaviour, update `README.md`
5. Open a pull request with a clear description of what changed and why

## Running tests

The test suite uses [bats-core](https://github.com/bats-core/bats-core), which is included in `tools/`:

```bash
make test
```

Or run a specific test file:

```bash
tools/bats-core/bin/bats tests/test_snapshot.bats
```

Tests mock Podman — no container runtime is needed to run them.

## Code style

- The tool is written in bash — keep it readable and avoid unnecessary complexity
- Follow the existing logging pattern: `log_info`, `log_debug`, `log_error` in every subcommand
- Every new subcommand must have tests in `tests/`
- Do not add dependencies beyond what is available on a standard Linux system
