SCRIPT   := src/claude-sandbox
DESTDIR  ?= $(HOME)/.local/bin
TOOLS    := tools
BATS     := $(shell command -v bats 2>/dev/null || echo $(TOOLS)/bats-core/bin/bats)

.PHONY: all setup test install lint clean

all: $(SCRIPT)

$(SCRIPT):
	chmod +x $@

# Install test dependencies into tools/ so they survive container restarts.
setup:
	@mkdir -p $(TOOLS)
	@if [ ! -x "$(TOOLS)/bats-core/bin/bats" ]; then \
		echo "Installing bats-core into $(TOOLS)/bats-core ..."; \
		git clone --depth 1 https://github.com/bats-core/bats-core.git $(TOOLS)/bats-core; \
	else \
		echo "bats-core already installed at $(TOOLS)/bats-core"; \
	fi

test:
	@if [ ! -x "$(BATS)" ]; then \
		echo "Error: bats not found. Run 'make setup' first."; exit 1; \
	fi
	$(BATS) tests/

lint:
	shellcheck $(SCRIPT)

install: $(SCRIPT)
	install -Dm755 $(SCRIPT) $(DESTDIR)/claude-sandbox
	@echo "Installed to $(DESTDIR)/claude-sandbox"
	@echo "Run 'claude-sandbox init' to complete setup."

clean:
	@echo "Nothing to clean."
