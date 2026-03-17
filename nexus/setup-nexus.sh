#!/bin/bash
# =============================================================================
# nexus/setup-nexus.sh
# Provisions Nexus repositories and Docker registry via REST API
# Run from host after Nexus is healthy
# =============================================================================

set -euo pipefail

NEXUS_URL="${NEXUS_URL:-http://localhost:8081}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-NexusDemo2024!}"

# Nexus 3 first-run writes a random admin password here
NEXUS_CONTAINER="${NEXUS_CONTAINER:-cicd_nexus}"

echo "================================================"
echo "  Nexus Repository Manager Setup"
echo "================================================"

# ---- Retrieve initial admin password ---------------------------------------
echo "🔑 Retrieving initial admin password..."
INITIAL_PASS=$(docker exec "${NEXUS_CONTAINER}" \
  cat /nexus-data/admin.password 2>/dev/null || echo "")

if [ -z "$INITIAL_PASS" ]; then
  echo "ℹ️  admin.password not found — assuming already configured."
  INITIAL_PASS="admin123"
fi

# ---- Update admin password -------------------------------------------------
echo "🔐 Setting admin password..."
curl -sf -X PUT \
  "${NEXUS_URL}/service/rest/v1/security/users/admin/change-password" \
  -H "Content-Type: text/plain" \
  -u "admin:${INITIAL_PASS}" \
  -d "${NEXUS_PASS}" || echo "   (Password may already be set)"

# ---- Helper function -------------------------------------------------------
nexus_api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [ -n "$data" ]; then
    curl -sf -X "$method" \
      "${NEXUS_URL}/service/rest/${path}" \
      -H "Content-Type: application/json" \
      -u "${NEXUS_USER}:${NEXUS_PASS}" \
      -d "$data"
  else
    curl -sf -X "$method" \
      "${NEXUS_URL}/service/rest/${path}" \
      -u "${NEXUS_USER}:${NEXUS_PASS}"
  fi
}

# ---- Create Maven2 hosted repositories ------------------------------------
echo ""
echo "📦 Creating Maven repositories..."

# Releases repo
nexus_api POST "v1/repositories/maven/hosted" '{
  "name": "demo-releases",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow_once"
  },
  "maven": {
    "versionPolicy": "RELEASE",
    "layoutPolicy": "STRICT"
  }
}' 2>/dev/null && echo "  ✅ demo-releases created" || echo "  ℹ️  demo-releases already exists"

# Snapshots repo
nexus_api POST "v1/repositories/maven/hosted" '{
  "name": "demo-snapshots",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow"
  },
  "maven": {
    "versionPolicy": "SNAPSHOT",
    "layoutPolicy": "STRICT"
  }
}' 2>/dev/null && echo "  ✅ demo-snapshots created" || echo "  ℹ️  demo-snapshots already exists"

# ---- Create Docker hosted registry ----------------------------------------
echo ""
echo "🐳 Creating Docker registry..."

nexus_api POST "v1/repositories/docker/hosted" '{
  "name": "demo-docker",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow"
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": 8082
  }
}' 2>/dev/null && echo "  ✅ demo-docker registry created" || echo "  ℹ️  demo-docker already exists"

# ---- Enable anonymous access (for demo) ------------------------------------
echo ""
echo "🔓 Enabling anonymous read access..."
nexus_api PUT "v1/security/anonymous" '{
  "enabled": true,
  "userId": "anonymous",
  "realmName": "NexusAuthorizingRealm"
}' 2>/dev/null && echo "  ✅ Anonymous access enabled" || true

# ---- Enable Docker realm ---------------------------------------------------
echo "🔐 Enabling Docker Bearer Token realm..."
nexus_api PUT "v1/security/realms/active" \
  '["NexusAuthorizingRealm","DockerToken"]' \
  2>/dev/null && echo "  ✅ Docker realm enabled" || true

# ---- Print summary ---------------------------------------------------------
echo ""
echo "================================================"
echo "  ✅ Nexus setup complete!"
echo ""
echo "  UI:             ${NEXUS_URL}"
echo "  Credentials:    ${NEXUS_USER} / ${NEXUS_PASS}"
echo ""
echo "  Repositories:"
echo "    Maven:  demo-releases, demo-snapshots"
echo "    Docker: ${NEXUS_URL%:*}:8082 (demo-docker)"
echo "================================================"

# ---- Show example upload commands ------------------------------------------
echo ""
echo "Example: Upload JAR manually"
echo "  mvn deploy:deploy-file \\"
echo "    -DgroupId=com.cicd.demo \\"
echo "    -DartifactId=demo-app \\"
echo "    -Dversion=1.0.0 \\"
echo "    -Dpackaging=jar \\"
echo "    -Dfile=demo-app-1.0.0.jar \\"
echo "    -DrepositoryId=nexus \\"
echo "    -Durl=${NEXUS_URL}/repository/demo-releases"
echo ""
echo "Example: Upload via curl"
echo "  curl -u ${NEXUS_USER}:${NEXUS_PASS} \\"
echo "    --upload-file demo-app-1.0.0.jar \\"
echo "    \"${NEXUS_URL}/repository/demo-releases/com/cicd/demo/demo-app/1.0.0/demo-app-1.0.0.jar\""
