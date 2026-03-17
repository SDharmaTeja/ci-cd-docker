#!/bin/bash
# =============================================================================
# setup.sh - CI/CD Demo Environment Setup (Linux / macOS)
#
# Usage:
#   chmod +x setup.sh && ./setup.sh
#
# Flags:
#   --skip-pull       Skip docker image pulls
#   --skip-provision  Skip GitLab/Nexus/Chef provisioning
#   --help            Show usage
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours (plain names, no unicode)
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()   { echo -e "${BLUE}[INFO]${NC} $*"; }
header() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}\n"; }

# ---------------------------------------------------------------------------
# Script directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
COMPOSE_FILE="docker-compose.yml"
GITLAB_URL="http://localhost:8080"
JENKINS_URL="http://localhost:8090"
NEXUS_URL="http://localhost:8081"
CHEF_URL="http://localhost:8100"
SUPERMARKET_URL="http://localhost:8200"

GITLAB_PASS="CicdDemo2024!"
NEXUS_PASS="NexusDemo2024!"
JENKINS_PASS="CicdDemo2024!"

MIN_RAM_GB=8
MIN_DISK_GB=20

SKIP_PULL=false
SKIP_PROVISION=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --skip-pull)      SKIP_PULL=true ;;
        --skip-provision) SKIP_PROVISION=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-pull] [--skip-provision] [--help]"
            echo "  --skip-pull       Skip docker image pulls"
            echo "  --skip-provision  Skip GitLab/Nexus/Chef provisioning"
            exit 0
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
    echo -e "${CYAN}"
    echo "+----------------------------------------------------------+"
    echo "|       CI/CD DEMO ENVIRONMENT - SETUP SCRIPT             |"
    echo "|  GitLab | Jenkins | Nexus | Chef Server | Supermarket   |"
    echo "+----------------------------------------------------------+"
    echo -e "${NC}"
}

# ---------------------------------------------------------------------------
# Install helpers
# ---------------------------------------------------------------------------
install_docker() {
    if [ "$(uname -s)" = "Darwin" ]; then
        error "Please install Docker Desktop for Mac: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    info "Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | sudo bash
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker
    log "Docker installed. You may need to log out and back in."
}

install_docker_compose() {
    local version="v2.24.0"
    local os
    os="$(uname -s)"
    local arch
    arch="$(uname -m)"
    info "Installing Docker Compose ${version}..."
    sudo curl -SL \
        "https://github.com/docker/compose/releases/download/${version}/docker-compose-${os}-${arch}" \
        -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log "docker-compose ${version} installed."
}

install_tool() {
    local tool="$1"
    if [ "$(uname -s)" = "Darwin" ]; then
        brew install "$tool" 2>/dev/null || warn "Could not install ${tool} via brew"
    elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y "$tool" 2>/dev/null || warn "Could not install ${tool}"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "$tool" 2>/dev/null || warn "Could not install ${tool}"
    else
        warn "Cannot auto-install ${tool} - please install manually"
    fi
}

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
check_prerequisites() {
    header "Checking Prerequisites"

    local os
    os="$(uname -s)"
    info "Operating system: ${os}"

    # Docker
    if ! command -v docker &>/dev/null; then
        warn "Docker not found - installing..."
        install_docker
    else
        local docker_ver
        docker_ver=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log "Docker ${docker_ver} found."
    fi

    # Docker daemon
    if ! docker info &>/dev/null; then
        warn "Docker daemon not running - starting..."
        if [ "$os" = "Darwin" ]; then
            open -a Docker
            info "Waiting for Docker Desktop to start..."
            local attempts=0
            until docker info &>/dev/null; do
                attempts=$((attempts + 1))
                if [ $attempts -ge 30 ]; then
                    error "Docker Desktop did not start in time."
                    exit 1
                fi
                sleep 3
            done
        else
            sudo systemctl start docker || sudo service docker start
            sleep 5
        fi
    fi
    log "Docker daemon is running."

    # Docker Compose
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        log "Docker Compose plugin found."
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        log "docker-compose standalone found."
    else
        warn "Docker Compose not found - installing..."
        install_docker_compose
        COMPOSE_CMD="docker-compose"
    fi

    # Other tools
    for tool in git curl jq python3; do
        if command -v "$tool" &>/dev/null; then
            log "${tool} found."
        else
            warn "${tool} not found - attempting install..."
            install_tool "$tool"
        fi
    done

    log "Prerequisites check complete."
}

# ---------------------------------------------------------------------------
# Resource validation
# ---------------------------------------------------------------------------
check_resources() {
    header "Validating System Resources"

    local os
    os="$(uname -s)"

    # RAM
    local ram_gb=0
    if [ "$os" = "Darwin" ]; then
        local ram_bytes
        ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        ram_gb=$(( ram_bytes / 1024 / 1024 / 1024 ))
    else
        local ram_kb
        ram_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
        ram_gb=$(( ram_kb / 1024 / 1024 ))
    fi

    if [ "$ram_gb" -lt "$MIN_RAM_GB" ]; then
        warn "Only ${ram_gb}GB RAM. Recommended: ${MIN_RAM_GB}GB+ for all services."
    else
        log "RAM: ${ram_gb}GB"
    fi

    # Disk
    local disk_avail
    disk_avail=$(df -BG "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2{gsub("G",""); print $4}' || echo 0)
    if [ "${disk_avail:-0}" -lt "$MIN_DISK_GB" ]; then
        warn "Only ${disk_avail}GB free disk. Recommended: ${MIN_DISK_GB}GB+"
    else
        log "Free disk: ${disk_avail}GB"
    fi

    # Port conflicts
    local ports=(8080 8081 8082 8090 8100 8200 2200 2222 50000)
    for port in "${ports[@]}"; do
        if lsof -i :"$port" &>/dev/null 2>&1; then
            warn "Port ${port} is already in use - check for conflicts"
        fi
    done
    log "Port check complete."
}

# ---------------------------------------------------------------------------
# Prepare directories
# ---------------------------------------------------------------------------
prepare_directories() {
    header "Preparing Directory Structure"

    local dirs=(
        "chef/keys"
        "chef/server-config"
        "chef-server"
        "chef-supermarket/api"
        "chef-supermarket/supermarket-ui"
        "nexus"
        "gitlab"
        "postgres"
    )

    for d in "${dirs[@]}"; do
        mkdir -p "$d"
    done

    # Make scripts executable
    chmod +x postgres/init-multiple-dbs.sh  2>/dev/null || true
    chmod +x nexus/setup-nexus.sh           2>/dev/null || true
    chmod +x gitlab/setup-gitlab.sh         2>/dev/null || true
    chmod +x chef/setup-chef-server.sh      2>/dev/null || true
    chmod +x chef-server/entrypoint.sh      2>/dev/null || true

    log "Directories ready."
}

# ---------------------------------------------------------------------------
# Pull images
# ---------------------------------------------------------------------------
pull_images() {
    header "Pulling Docker Images"
    info "This may take 10-20 minutes on first run (GitLab alone is ~2GB)..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" pull 2>&1 || warn "Some images could not be pulled (custom images are built locally)."
    log "Image pull complete."
}

# ---------------------------------------------------------------------------
# Build and start services
# ---------------------------------------------------------------------------
start_services() {
    header "Building and Starting Services"

    info "Building custom images (Jenkins, Chef Server, Chef Supermarket)..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" build 2>&1 || warn "Build had warnings - check output above."
    log "Custom images built."

    info "Starting all containers..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" up -d

    log "All containers started."
    echo ""
    $COMPOSE_CMD -f "$COMPOSE_FILE" ps
}

# ---------------------------------------------------------------------------
# Wait for HTTP endpoint
# ---------------------------------------------------------------------------
wait_for_http() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-60}"
    local interval="${4:-10}"

    info "Waiting for ${name} at ${url} ..."
    local attempt=0
    until curl -sf --max-time 5 "$url" >/dev/null 2>&1; do
        attempt=$(( attempt + 1 ))
        if [ "$attempt" -ge "$max_attempts" ]; then
            warn "${name} did not respond after $(( max_attempts * interval ))s - continuing anyway"
            return 0
        fi
        printf "   [%d/%d] %s not ready - waiting %ds...\n" \
            "$attempt" "$max_attempts" "$name" "$interval"
        sleep "$interval"
    done
    log "${name} is ready!"
}

# ---------------------------------------------------------------------------
# Wait for all services
# ---------------------------------------------------------------------------
wait_for_services() {
    header "Waiting for Services to Become Healthy"

    info "Giving containers 20 seconds to initialise..."
    sleep 20

    wait_for_http "Nexus"           "${NEXUS_URL}/service/rest/v1/status" 60 10
    wait_for_http "GitLab"          "${GITLAB_URL}/-/health"              90 15
    wait_for_http "Jenkins"         "${JENKINS_URL}/login"                60 10
    wait_for_http "Chef Supermarket" "${SUPERMARKET_URL}/api/v1/status"   10  5

    info "Chef Server takes 3-5 minutes on first boot..."
    wait_for_http "Chef Server"     "${CHEF_URL}/_status"                 60 15

    log "All services checked."
}

# ---------------------------------------------------------------------------
# Provision Nexus
# ---------------------------------------------------------------------------
provision_nexus() {
    header "Provisioning Nexus"

    if [ -f ./nexus/setup-nexus.sh ]; then
        NEXUS_URL="$NEXUS_URL" \
        NEXUS_PASS="$NEXUS_PASS" \
        NEXUS_CONTAINER="cicd_nexus" \
            bash nexus/setup-nexus.sh
    else
        warn "nexus/setup-nexus.sh not found - skipping"
    fi

    log "Nexus provisioning complete."
}

# ---------------------------------------------------------------------------
# Provision GitLab
# ---------------------------------------------------------------------------
provision_gitlab() {
    header "Provisioning GitLab"

    if [ -f ./gitlab/setup-gitlab.sh ]; then
        GITLAB_URL="$GITLAB_URL" \
        GITLAB_ROOT_PASS="$GITLAB_PASS" \
        APP_DIR="./app" \
            bash gitlab/setup-gitlab.sh
    else
        warn "gitlab/setup-gitlab.sh not found - skipping"
    fi

    log "GitLab provisioning complete."
}

# ---------------------------------------------------------------------------
# Retrieve Chef keys from container
# ---------------------------------------------------------------------------
retrieve_chef_keys() {
    header "Retrieving Chef Server Keys"

    mkdir -p chef/keys

    local keys=("jenkins.pem" "admin.pem" "cicd-demo-validator.pem")
    for key in "${keys[@]}"; do
        if docker cp "cicd_chef_server:/etc/opscode/keys/${key}" "chef/keys/${key}" 2>/dev/null; then
            log "Copied: chef/keys/${key}"
        else
            warn "Could not copy ${key} - Chef Server may still be initialising"
        fi
    done
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "+==================================================================+"
    echo "|          CI/CD DEMO ENVIRONMENT IS READY!                       |"
    echo "+==================================================================+"
    echo "|  SERVICE URLS                                                    |"
    echo "+------------------------------------------------------------------+"
    printf "|  %-20s %-44s|\n" "GitLab CE:"        "${GITLAB_URL}"
    printf "|  %-20s %-44s|\n" "Jenkins:"          "${JENKINS_URL}"
    printf "|  %-20s %-44s|\n" "Nexus:"            "${NEXUS_URL}"
    printf "|  %-20s %-44s|\n" "Chef Server:"      "${CHEF_URL}"
    printf "|  %-20s %-44s|\n" "Chef Supermarket:" "${SUPERMARKET_URL}"
    echo "+------------------------------------------------------------------+"
    echo "|  CREDENTIALS                                                     |"
    echo "+------------------------------------------------------------------+"
    printf "|  %-20s %-44s|\n" "GitLab root:"      "root / ${GITLAB_PASS}"
    printf "|  %-20s %-44s|\n" "Jenkins admin:"    "admin / ${JENKINS_PASS}"
    printf "|  %-20s %-44s|\n" "Nexus admin:"      "admin / ${NEXUS_PASS}"
    printf "|  %-20s %-44s|\n" "Chef admin:"       "admin / ChefAdmin2024!"
    echo "+------------------------------------------------------------------+"
    echo "|  MANAGEMENT COMMANDS                                             |"
    echo "+------------------------------------------------------------------+"
    echo "|  Stop:    docker compose down                                    |"
    echo "|  Restart: docker compose up -d                                   |"
    echo "|  Logs:    docker compose logs -f <service>                       |"
    echo "|  Destroy: docker compose down -v                                 |"
    echo "+==================================================================+"
    echo -e "${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    print_banner
    check_prerequisites
    check_resources
    prepare_directories

    if [ "$SKIP_PULL" = false ]; then
        pull_images || warn "Image pull had issues - continuing"
    fi

    start_services
    wait_for_services

    if [ "$SKIP_PROVISION" = false ]; then
        provision_nexus  || warn "Nexus provisioning had issues"
        provision_gitlab || warn "GitLab provisioning had issues"
        retrieve_chef_keys || warn "Chef key retrieval had issues"
    fi

    print_summary
}

main "$@"
