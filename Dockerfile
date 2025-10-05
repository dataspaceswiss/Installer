# Use Ubuntu as base image
FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    sudo \
    cron \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Copy only the installer script
COPY install.sh /tmp/install.sh

# Make script executable
RUN chmod +x /tmp/install.sh

# Set the installer as the default command
CMD ["/tmp/install.sh"]
