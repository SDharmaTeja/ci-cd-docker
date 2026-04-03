#!/bin/bash
set -euxo pipefail

exec > /var/log/user-data.log 2>&1

echo "Starting userdata script at $(date)"

# Wait for cloud-init networking/package sources to settle
sleep 10

# Update package index
apt-get update -y

# Install base packages
apt-get install -y \
  ca-certificates \
  curl \
  unzip \
  gnupg \
  lsb-release \
  software-properties-common \
  git \
  gnupg2 \
  locales \
  iproute2

# Install AWS CLI v2
cd /tmp
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install --update

# Install Amazon SSM Agent
cd /tmp
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service || true

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# Optional: allow ubuntu user to run docker without sudo
usermod -aG docker ubuntu || true

# Validate installations
aws --version
git --version
docker --version
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service --no-pager || true

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

cd /tmp
export CHEF_LICENSE=accept
CHEF_URL="https://packages.chef.io/files/stable/chef-server/15.10.91/ubuntu/20.04/chef-server-core_15.10.91-1_amd64.deb"

wget $CHEF_URL

# ================================
# Install Chef Server
# ================================
dpkg -i chef-server-core_*.deb

# ================================
# Configure Chef Server
# ================================
cat <<EOF > /etc/opscode/chef-server.rb

# Set hostname (auto-detect EC2 private IP)
api_fqdn "$(hostname -f)"

# Fix PostgreSQL listen issue
postgresql['listen_address'] = '127.0.0.1'

# Elasticsearch heap (minimum safe)
elasticsearch['heap_size'] = 1024

# Optional tuning
nginx['enable_non_ssl'] = true

EOF


CHEF_ORG="${CHEF_ORG:-cicd-demo}"
CHEF_ORG_FULL="${CHEF_ORG_FULL:-CICD Demo Organization}"
CHEF_ADMIN_USER="${CHEF_ADMIN_USER:-admin}"
CHEF_ADMIN_PASS="${CHEF_ADMIN_PASS:-ChefAdmin2024!}"
KEYS_DIR="/etc/opscode/keys"
MARKER="/var/opt/opscode/.configured"

mkdir -p "$KEYS_DIR"

echo "============================================"
echo "  Chef Infra Server — Starting"
echo "============================================"

# ---- First-run: reconfigure ------------------------------------------------
if [ ! -f "$MARKER" ]; then
    echo "⚙️  First run — running chef-server-ctl reconfigure..."
    chef-server-ctl reconfigure --accept-license

    echo "👤 Creating admin user..."
    chef-server-ctl user-create \
        "$CHEF_ADMIN_USER" Admin User \
        "admin@cicd.demo" \
        "$CHEF_ADMIN_PASS" \
        --filename "${KEYS_DIR}/admin.pem" 2>/dev/null || \
        echo "   Admin user may already exist."

    echo "📦 Creating organisation: ${CHEF_ORG}"
    chef-server-ctl org-create \
        "$CHEF_ORG" \
        "$CHEF_ORG_FULL" \
        --association-user "$CHEF_ADMIN_USER" \
        --filename "${KEYS_DIR}/${CHEF_ORG}-validator.pem" 2>/dev/null || \
        echo "   Org may already exist."

    echo "👤 Creating jenkins user..."
    chef-server-ctl user-create \
        jenkins Jenkins Automation \
        "jenkins@cicd.demo" \
        "ChefJenkins2024!" \
        --filename "${KEYS_DIR}/jenkins.pem" 2>/dev/null || \
        echo "   Jenkins user may already exist."

    echo "🔗 Adding jenkins to org as admin..."
    chef-server-ctl org-user-add "$CHEF_ORG" jenkins --admin 2>/dev/null || true

    touch "$MARKER"
    echo "✅ First-run configuration complete."
else
    echo "ℹ️  Already configured — starting services..."
    chef-server-ctl start 2>/dev/null || true
fi

echo ""
echo "============================================"
echo "  Chef Server ready!"
echo "  Org:   ${CHEF_ORG}"
echo "  Keys:  ${KEYS_DIR}/"
echo "============================================"
