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

# Copy the whole directory
COPY ./templates/ /tmp/install/
COPY ./install.sh /tmp/install/install.sh
COPY ./test_install.sh /tmp/install/test_install.sh
RUN chmod +x /tmp/install/install.sh
RUN chmod +x /tmp/install/test_install.sh

# Set the installer as the default command
CMD ["/tmp/install/install.sh"]
