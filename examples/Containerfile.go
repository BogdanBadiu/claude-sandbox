FROM claude-ubuntu

# Go development environment.
#
# Usage:
#   claude-sandbox build go
#   claude-sandbox new my-app go
#
# Go is installed system-wide at /usr/local/go/bin/go.
# GOPATH is set to ~/go — binaries installed with 'go install' land in ~/go/bin,
# which is added to PATH via the shell profile written below.

ARG GO_VERSION=1.24.3

RUN sudo apt-get update && sudo apt-get install -y \
        gcc \
    && sudo rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
       | sudo tar -C /usr/local -xz

RUN echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' >> ~/.bashrc \
    && echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' >> ~/.profile
