#!/bin/bash
# =============================================================================
# chef-server/entrypoint.sh
# Initialises Chef Server on first run, then keeps it running
# =============================================================================

set -e

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

# Keep container alive by tailing the nginx log
tail -f /var/log/opscode/nginx/access.log 2>/dev/null || \
    tail -f /var/log/opscode/opscode-erchef/erchef.log 2>/dev/null || \
    sleep infinity
