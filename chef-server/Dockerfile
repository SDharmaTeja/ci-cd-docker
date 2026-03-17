# =============================================================================
# chef-server/Dockerfile
# Builds Chef Infra Server from official Chef packages (packages.chef.io)
# Base: Ubuntu 20.04 (focal) — required by Chef Server 15
# =============================================================================

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CHEF_LICENSE=accept

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg2 \
    apt-transport-https \
    ca-certificates \
    openssh-server \
    sudo \
    lsb-release \
    sysstat \
    && rm -rf /var/lib/apt/lists/*

# Download and install Chef Server from official packages.chef.io
# Using Chef Server 15.x (latest stable, free for up to 25 nodes)
RUN curl -fsSL https://packages.chef.io/files/stable/chef-server/15.9.27/ubuntu/20.04/chef-server-core_15.9.27-1_amd64.deb \
    -o /tmp/chef-server.deb \
    && dpkg -i /tmp/chef-server.deb \
    && rm /tmp/chef-server.deb

# Create chef-server configuration directory
RUN mkdir -p /etc/opscode /var/opt/opscode/nginx /var/log/opscode

# Copy default configuration
COPY chef-server.rb /etc/opscode/chef-server.rb

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Chef Server ports
EXPOSE 80 443

# Data persistence
VOLUME ["/var/opt/opscode", "/var/log/opscode", "/etc/opscode"]

ENTRYPOINT ["/entrypoint.sh"]
