FROM claude-ubuntu

# Java development environment with Maven.
#
# Usage:
#   claude-sandbox build java
#   claude-sandbox new my-app java
#
# Installs OpenJDK 21 (LTS) and Maven.
# For Gradle projects, replace maven with gradle in the apt install line.

RUN sudo apt-get update && sudo apt-get install -y \
        openjdk-21-jdk \
        maven \
    && sudo rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
