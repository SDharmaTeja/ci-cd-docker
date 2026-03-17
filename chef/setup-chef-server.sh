#!/bin/bash
# =============================================================================
# chef/setup-chef-server.sh
# Runs INSIDE the chef-server container to bootstrap org & user
# Called by setup.sh after Chef Server is healthy
# =============================================================================

set -euo pipefail

CHEF_ORG="cicd-demo"
CHEF_ORG_FULL="CICD Demo Organization"
CHEF_USER="jenkins"
CHEF_USER_FIRST="Jenkins"
CHEF_USER_LAST="Automation"
CHEF_USER_EMAIL="jenkins@cicd.demo"
CHEF_USER_PASS="ChefDemo2024!"
KEYS_DIR="/tmp/chef-keys"

mkdir -p "$KEYS_DIR"

echo "================================================"
echo "  Chef Server Bootstrap"
echo "================================================"

# ---- Wait for Chef Server to be fully configured ---------------------------
echo "⏳ Waiting for Chef Server reconfigure..."
until chef-server-ctl status 2>/dev/null | grep -q "run: opscode-erchef"; do
  echo "   Chef Server not ready yet..."
  sleep 10
done
echo "✅ Chef Server is running."

# ---- Create organisation ---------------------------------------------------
if ! chef-server-ctl org-list 2>/dev/null | grep -q "^${CHEF_ORG}$"; then
  echo "📦 Creating organisation: ${CHEF_ORG}"
  chef-server-ctl org-create \
    "${CHEF_ORG}" \
    "${CHEF_ORG_FULL}" \
    --filename "${KEYS_DIR}/${CHEF_ORG}-validator.pem"
  echo "✅ Organisation '${CHEF_ORG}' created."
else
  echo "ℹ️  Organisation '${CHEF_ORG}' already exists."
fi

# ---- Create Jenkins user ---------------------------------------------------
if ! chef-server-ctl user-list 2>/dev/null | grep -q "^${CHEF_USER}$"; then
  echo "👤 Creating user: ${CHEF_USER}"
  chef-server-ctl user-create \
    "${CHEF_USER}" \
    "${CHEF_USER_FIRST}" \
    "${CHEF_USER_LAST}" \
    "${CHEF_USER_EMAIL}" \
    "${CHEF_USER_PASS}" \
    --filename "${KEYS_DIR}/${CHEF_USER}.pem"
  echo "✅ User '${CHEF_USER}' created."
else
  echo "ℹ️  User '${CHEF_USER}' already exists."
  # Re-generate key
  chef-server-ctl user-key-create "${CHEF_USER}" \
    --key-name default \
    --output-file "${KEYS_DIR}/${CHEF_USER}.pem" 2>/dev/null || true
fi

# ---- Add Jenkins user to org -----------------------------------------------
echo "🔗 Adding ${CHEF_USER} to org ${CHEF_ORG} as admin..."
chef-server-ctl org-user-add \
  "${CHEF_ORG}" \
  "${CHEF_USER}" \
  --admin 2>/dev/null || echo "   (Already a member)"

# ---- Create admin user (for UI access) -------------------------------------
if ! chef-server-ctl user-list 2>/dev/null | grep -q "^admin$"; then
  echo "👤 Creating admin user..."
  chef-server-ctl user-create \
    admin Admin User \
    "admin@cicd.demo" \
    "ChefAdmin2024!" \
    --filename "${KEYS_DIR}/admin.pem"
  chef-server-ctl org-user-add "${CHEF_ORG}" admin --admin
fi

# ---- Print key paths -------------------------------------------------------
echo ""
echo "================================================"
echo "  ✅ Chef Server setup complete!"
echo "  Keys written to: ${KEYS_DIR}"
echo ""
echo "  Validator:  ${KEYS_DIR}/${CHEF_ORG}-validator.pem"
echo "  Jenkins:    ${KEYS_DIR}/${CHEF_USER}.pem"
echo "================================================"

# Copy keys to mounted volume so host can retrieve them
cp "${KEYS_DIR}"/*.pem /var/opt/opscode/keys/ 2>/dev/null || true
