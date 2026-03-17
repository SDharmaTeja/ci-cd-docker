# =============================================================================
# Jenkins Dockerfile — Pre-installs all required plugins
# =============================================================================
FROM jenkins/jenkins:2.440.2-lts-jdk17

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    docker.io \
    maven \
    nodejs \
    npm \
    ruby \
    ruby-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Chef Workstation (knife CLI)
RUN curl -L https://omnitruck.chef.io/install.sh | bash -s -- -P chef-workstation -v 23.10.1040 || \
    echo "Chef workstation install skipped — install manually if needed"

# Install knife-supermarket gem as fallback
RUN gem install knife-supermarket --no-document 2>/dev/null || true

USER jenkins

# Copy plugin list
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

# Install plugins using Jenkins plugin installer
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt \
    --verbose 2>&1 | tail -20 || echo "Some plugins may need manual install"

# Copy Groovy init scripts (auto-configuration)
COPY init.groovy.d/ /var/jenkins_home/init.groovy.d/

# Set Jenkins port
ENV JENKINS_OPTS="--httpPort=8090"
