#!/bin/bash
# =============================================================================
# gitlab/setup-gitlab.sh
# Creates demo project via GitLab API and pushes sample application
# =============================================================================

set -euo pipefail

GITLAB_URL="${GITLAB_URL:-http://localhost:8089}"
GITLAB_ROOT_PASS="${GITLAB_ROOT_PASS:-CicdDemo2024!}"
PROJECT_NAME="demo-app"
PROJECT_DESC="CI/CD Demo Application — Spring Boot"
APP_DIR="${APP_DIR:-./app}"

echo "================================================"
echo "  GitLab Project Setup"
echo "================================================"

# ---- Wait for GitLab API ---------------------------------------------------
echo "⏳ Waiting for GitLab API..."
until curl -sf "${GITLAB_URL}/-/health" > /dev/null 2>&1; do
  echo "   GitLab not ready..."
  sleep 10
done
echo "✅ GitLab is up."

# ---- Get root user token ---------------------------------------------------
echo "🔑 Obtaining API token..."
TOKEN_RESPONSE=$(curl -sf \
  --request POST "${GITLAB_URL}/oauth/token" \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "username=root" \
  --data-urlencode "password=${GITLAB_ROOT_PASS}" \
  2>/dev/null || echo '{"error":"oauth_not_ready"}')

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('access_token',''))
" 2>/dev/null || echo "")

# Fallback: create personal access token via rails console approach
if [ -z "$ACCESS_TOKEN" ]; then
  echo "ℹ️  OAuth not ready — creating personal access token via API..."
  # Try creating a PAT directly (available in newer GitLab versions)
  PAT_RESPONSE=$(curl -sf \
    --request POST "${GITLAB_URL}/api/v4/users/1/personal_access_tokens" \
    --header "PRIVATE-TOKEN: " \
    --header "Content-Type: application/json" \
    --data '{
      "name": "jenkins-token",
      "scopes": ["api", "read_repository", "write_repository"]
    }' 2>/dev/null || echo '{}')
  ACCESS_TOKEN=$(echo "$PAT_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('token',''))
" 2>/dev/null || echo "")
fi

if [ -z "$ACCESS_TOKEN" ]; then
  echo "⚠️  Could not get API token — using basic auth for project creation"
  AUTH_HEADER="Authorization: Basic $(echo -n root:${GITLAB_ROOT_PASS} | base64)"
else
  AUTH_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"
fi

# ---- Create project --------------------------------------------------------
echo "📁 Creating project '${PROJECT_NAME}'..."
PROJECT_RESPONSE=$(curl -sf \
  --request POST "${GITLAB_URL}/api/v4/projects" \
  --header "${AUTH_HEADER}" \
  --header "Content-Type: application/json" \
  --data "{
    \"name\": \"${PROJECT_NAME}\",
    \"description\": \"${PROJECT_DESC}\",
    \"visibility\": \"private\",
    \"initialize_with_readme\": false,
    \"default_branch\": \"main\"
  }" 2>/dev/null || echo '{}')

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('id',''))
" 2>/dev/null || echo "")

HTTP_URL=$(echo "$PROJECT_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('http_url_to_repo',''))
" 2>/dev/null || echo "${GITLAB_URL}/root/${PROJECT_NAME}.git")

if [ -z "$PROJECT_ID" ]; then
  echo "ℹ️  Project may already exist."
  HTTP_URL="${GITLAB_URL}/root/${PROJECT_NAME}.git"
else
  echo "✅ Project created (ID: ${PROJECT_ID})"
fi

# ---- Push sample application -----------------------------------------------
echo ""
echo "📤 Pushing sample application to GitLab..."

# Configure git credentials
git config --global user.email "jenkins@cicd.demo"
git config --global user.name  "Jenkins Automation"
git config --global credential.helper store

# Write credentials store
cat > ~/.git-credentials <<EOF
http://root:${GITLAB_ROOT_PASS}@${GITLAB_URL#http://}
EOF

WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

git init -b main
git remote add origin "${HTTP_URL}"

# Copy application files
cp -r "${APP_DIR}"/* .          2>/dev/null || true
cp "${APP_DIR}/../Jenkinsfile" . 2>/dev/null || true
cp "${APP_DIR}/../Dockerfile" .  2>/dev/null || true

# Copy Chef cookbook into repo
mkdir -p chef
cp -r "${APP_DIR}/../chef/cookbooks" chef/ 2>/dev/null || true

# Write .gitignore
cat > .gitignore <<'EOF'
target/
.m2/
*.class
*.jar
.DS_Store
.idea/
*.iml
node_modules/
EOF

git add -A
git commit -m "Initial commit — CI/CD demo application

Added:
- Spring Boot application (Java 17)
- Jenkinsfile (7-stage CI/CD pipeline)
- Dockerfile (multi-stage build)
- .gitlab-ci.yml
- Chef cookbook (myapp)
- Unit tests with JaCoCo coverage"

git push -u origin main --force

echo "✅ Application pushed to ${HTTP_URL}"

# ---- Create webhook to trigger Jenkins on push -----------------------------
echo ""
echo "🔗 Creating GitLab webhook → Jenkins..."
curl -sf \
  --request POST "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/hooks" \
  --header "${AUTH_HEADER}" \
  --header "Content-Type: application/json" \
  --data "{
    \"url\": \"http://172.20.0.21:8090/project/demo-cicd-pipeline\",
    \"push_events\": true,
    \"merge_requests_events\": true,
    \"token\": \"gitlab-webhook-token\"
  }" 2>/dev/null && echo "✅ Webhook created." || echo "⚠️  Webhook creation skipped."

# ---- Create developer user -------------------------------------------------
echo ""
echo "👤 Creating developer user..."
curl -sf \
  --request POST "${GITLAB_URL}/api/v4/users" \
  --header "${AUTH_HEADER}" \
  --header "Content-Type: application/json" \
  --data '{
    "name": "Dev User",
    "username": "developer",
    "email": "developer@cicd.demo",
    "password": "Developer2024!",
    "skip_confirmation": true
  }' 2>/dev/null && echo "✅ Developer user created." || echo "ℹ️  User may already exist."

# Cleanup
cd /
rm -rf "$WORK_DIR"

echo ""
echo "================================================"
echo "  ✅ GitLab setup complete!"
echo ""
echo "  URL:     ${GITLAB_URL}"
echo "  Repo:    ${HTTP_URL}"
echo "  Users:   root / ${GITLAB_ROOT_PASS}"
echo "           developer / Developer2024!"
echo "================================================"
