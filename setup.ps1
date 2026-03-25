#Requires -Version 5.1
# =============================================================================
# setup.ps1 - CI/CD Demo Environment Setup (Windows PowerShell)
#
# Usage (run as Administrator):
#   Set-ExecutionPolicy RemoteSigned -Scope Process
#   .\setup.ps1
#
# Flags:
#   -SkipPull       Skip docker image pulls
#   -SkipProvision  Skip GitLab/Nexus auto-provisioning
#   -Help           Show usage
# =============================================================================

param(
    [switch]$SkipPull,
    [switch]$SkipProvision,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$GitLabUrl       = "http://localhost:8089"
$JenkinsUrl      = "http://localhost:8090"
$NexusUrl        = "http://localhost:8081"
$ChefUrl         = "http://localhost:8100"
$SupermarketUrl  = "http://localhost:8200"

$GitLabPass      = "CicdDemo2024!"
$JenkinsPass     = "CicdDemo2024!"
$NexusPass       = "NexusDemo2024!"

$MinRamGB        = 8
$MinDiskGB       = 20
$ComposeFile     = "docker-compose.yml"

$script:ComposeCmd = "docker compose"

# ---------------------------------------------------------------------------
# Logging helpers  (plain ASCII only)
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$msg)
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Write-Warn {
    param([string]$msg)
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Write-Info {
    param([string]$msg)
    Write-Host "[INFO] $msg" -ForegroundColor Blue
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
function Show-Banner {
    Write-Host ""
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "|       CI/CD DEMO ENVIRONMENT - SETUP SCRIPT             |" -ForegroundColor Cyan
    Write-Host "|  GitLab | Jenkins | Nexus | Chef Server | Supermarket   |" -ForegroundColor Cyan
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if ($Help) {
    Write-Host "Usage: .\setup.ps1 [-SkipPull] [-SkipProvision] [-Help]"
    Write-Host "  -SkipPull       Skip docker image pulls (use cached images)"
    Write-Host "  -SkipProvision  Skip GitLab/Nexus/Chef auto-provisioning"
    Write-Host "  -Help           Show this help message"
    exit 0
}

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
function Test-Prerequisites {
    Write-Header "Checking Prerequisites"

    # Docker
    $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        Write-Err "Docker not found!"
        Write-Info "Download Docker Desktop from: https://www.docker.com/products/docker-desktop"
        Write-Info "After installing, restart this script."
        exit 1
    }

    try {
        $dockerVer = (docker --version 2>&1) -replace "Docker version ", "" -replace ",.*", ""
        Write-OK "Docker $dockerVer found."
    }
    catch {
        Write-Err "Could not get Docker version: $_"
        exit 1
    }

    # Docker daemon
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Docker daemon is not running. Please start Docker Desktop."
        exit 1
    }
    Write-OK "Docker daemon is running."

    # Docker Compose
    $composeTest = docker compose version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $script:ComposeCmd = "docker compose"
        Write-OK "Docker Compose plugin found."
    }
    else {
        $dcCmd = Get-Command docker-compose -ErrorAction SilentlyContinue
        if ($dcCmd) {
            $script:ComposeCmd = "docker-compose"
            Write-OK "docker-compose standalone found."
        }
        else {
            Write-Err "Docker Compose not found. Install Docker Desktop (includes Compose)."
            exit 1
        }
    }

    # Git
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Warn "git not found. Attempting install via winget..."
        try {
            winget install --id Git.Git -e --source winget --silent 2>&1 | Out-Null
            $env:PATH = $env:PATH + ";C:\Program Files\Git\bin"
            Write-OK "git installed."
        }
        catch {
            Write-Warn "Could not auto-install git. Download from https://git-scm.com"
        }
    }
    else {
        Write-OK "git found."
    }

    # curl (built into Windows 10+)
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd) {
        Write-OK "curl.exe found."
    }
    else {
        Write-Info "curl.exe not found - will use Invoke-WebRequest instead."
    }

    Write-OK "Prerequisites check complete."
}

# ---------------------------------------------------------------------------
# Resource validation
# ---------------------------------------------------------------------------
function Test-Resources {
    Write-Header "Validating System Resources"

    # RAM
    try {
        $ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $ramGB = [math]::Round($ramBytes / 1GB, 1)
        if ($ramGB -lt $MinRamGB) {
            Write-Warn "Only ${ramGB}GB RAM detected. Recommended: ${MinRamGB}GB+"
            Write-Warn "GitLab and Chef Server may be slow on low-memory systems."
        }
        else {
            Write-OK "RAM: ${ramGB}GB"
        }
    }
    catch {
        Write-Warn "Could not check RAM: $_"
    }

    # Disk space
    try {
        $driveLetter = (Get-Location).Drive.Name
        $disk = Get-PSDrive $driveLetter -ErrorAction Stop
        $freeGB = [math]::Round($disk.Free / 1GB, 1)
        if ($freeGB -lt $MinDiskGB) {
            Write-Warn "Only ${freeGB}GB free disk. Recommended: ${MinDiskGB}GB+"
        }
        else {
            Write-OK "Free disk: ${freeGB}GB"
        }
    }
    catch {
        Write-Warn "Could not check disk space: $_"
    }

    # Port conflicts
    $ports = @(8089, 8081, 8082, 8090, 8100, 8200, 2200, 2222, 50000)
    $conflicts = @()
    foreach ($port in $ports) {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) {
            $conflicts += $port
        }
    }
    if ($conflicts.Count -gt 0) {
        Write-Warn "Ports already in use: $($conflicts -join ', ')"
        Write-Warn "Edit docker-compose.yml to change conflicting host ports."
    }
    else {
        Write-OK "All required ports are available."
    }
}

# ---------------------------------------------------------------------------
# Prepare directories
# ---------------------------------------------------------------------------
function Initialize-Directories {
    Write-Header "Preparing Directory Structure"

    $dirs = @(
        "chef\keys",
        "chef\server-config",
        "chef-server",
        "chef-supermarket\api",
        "chef-supermarket\supermarket-ui",
        "nexus",
        "gitlab",
        "postgres"
    )

    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Write-Info "Created directory: $d"
        }
    }

    Write-OK "Directories ready."
}

# ---------------------------------------------------------------------------
# Pull Docker images
# ---------------------------------------------------------------------------
function Invoke-PullImages {
    Write-Header "Pulling Docker Images"
    Write-Info "This may take 10-20 minutes on first run..."
    Write-Info "GitLab alone is ~2GB."

    $cmdArgs = "-f `"$ComposeFile`" pull"
    $result = Invoke-Expression "$($script:ComposeCmd) $cmdArgs" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Some images could not be pulled (custom images are built locally)."
    }
    else {
        Write-OK "Images pulled successfully."
    }
}

# ---------------------------------------------------------------------------
# Build and start services
# ---------------------------------------------------------------------------
function Start-Services {
    Write-Header "Building and Starting CI/CD Services"

    Write-Info "Building custom images (Jenkins, Chef Server, Chef Supermarket)..."
    $buildResult = Invoke-Expression "$($script:ComposeCmd) -f `"$ComposeFile`" build" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Build had warnings - continuing. Check output above."
    }
    else {
        Write-OK "Custom images built."
    }

    Write-Info "Starting all services in background..."
    $upResult = Invoke-Expression "$($script:ComposeCmd) -f `"$ComposeFile`" up -d" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to start services!"
        Write-Err $upResult
        exit 1
    }

    Write-OK "All containers started."
    Write-Host ""
    Invoke-Expression "$($script:ComposeCmd) -f `"$ComposeFile`" ps"
}

# ---------------------------------------------------------------------------
# Wait for a service HTTP endpoint
# ---------------------------------------------------------------------------
function Wait-ForHttp {
    param(
        [string]$ServiceName,
        [string]$Url,
        [int]$MaxAttempts = 60,
        [int]$IntervalSec = 10
    )

    Write-Info "Waiting for $ServiceName at $Url ..."
    $attempt = 0

    do {
        $attempt++
        $ready = $false

        try {
            $response = Invoke-WebRequest `
                -Uri $Url `
                -TimeoutSec 5 `
                -UseBasicParsing `
                -ErrorAction Stop
            if ($response.StatusCode -lt 500) {
                $ready = $true
            }
        }
        catch {
            # Not ready yet
        }

        if ($ready) {
            Write-OK "$ServiceName is ready!"
            return $true
        }

        if ($attempt -ge $MaxAttempts) {
            Write-Warn "$ServiceName did not respond after $($MaxAttempts * $IntervalSec)s - continuing anyway."
            return $false
        }

        $remaining = $MaxAttempts - $attempt
        Write-Host "   Attempt $attempt/$MaxAttempts - $ServiceName not ready yet, waiting ${IntervalSec}s... ($remaining attempts left)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $IntervalSec

    } while ($true)
}

# ---------------------------------------------------------------------------
# Wait for all services
# ---------------------------------------------------------------------------
function Wait-ForAllServices {
    Write-Header "Waiting for Services to Become Healthy"

    Write-Info "Giving containers 20 seconds to initialise..."
    Start-Sleep -Seconds 20

    Wait-ForHttp `
        -ServiceName "Nexus" `
        -Url "$NexusUrl/service/rest/v1/status" `
        -MaxAttempts 60 `
        -IntervalSec 10

    Wait-ForHttp `
        -ServiceName "GitLab" `
        -Url "$GitLabUrl/-/health" `
        -MaxAttempts 90 `
        -IntervalSec 15

    Wait-ForHttp `
        -ServiceName "Jenkins" `
        -Url "$JenkinsUrl/login" `
        -MaxAttempts 60 `
        -IntervalSec 10

    Wait-ForHttp `
        -ServiceName "Chef Supermarket" `
        -Url "$SupermarketUrl/api/v1/status" `
        -MaxAttempts 10 `
        -IntervalSec 5

    Write-Info "Chef Server takes 3-5 minutes on first boot (package reconfigure)..."
    Wait-ForHttp `
        -ServiceName "Chef Server" `
        -Url "$ChefUrl/_status" `
        -MaxAttempts 60 `
        -IntervalSec 15

    Write-OK "All services checked."
}

# ---------------------------------------------------------------------------
# Provision Nexus repositories
# ---------------------------------------------------------------------------
function Invoke-NexusSetup {
    Write-Header "Provisioning Nexus Repository Manager"

    # Retrieve initial admin password from container
    Write-Info "Retrieving initial Nexus admin password..."
    $initialPass = ""
    try {
        $initialPass = (docker exec cicd_nexus cat /nexus-data/admin.password 2>$null).Trim()
    }
    catch {}

    if ([string]::IsNullOrEmpty($initialPass)) {
        Write-Info "admin.password not found - assuming already configured."
        $initialPass = "admin123"
    }
    else {
        Write-OK "Got initial Nexus password."
    }

    # Build auth header helper
    function Get-BasicAuth {
        param([string]$user, [string]$pass)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("${user}:${pass}")
        return "Basic " + [Convert]::ToBase64String($bytes)
    }

    # Change admin password
    Write-Info "Setting Nexus admin password..."
    try {
        $changeHeaders = @{
            "Authorization" = (Get-BasicAuth "admin" $initialPass)
            "Content-Type"  = "text/plain"
        }
        Invoke-RestMethod `
            -Method PUT `
            -Uri "$NexusUrl/service/rest/v1/security/users/admin/change-password" `
            -Headers $changeHeaders `
            -Body $NexusPass `
            -UseBasicParsing `
            -ErrorAction Stop | Out-Null
        Write-OK "Nexus admin password set to: $NexusPass"
    }
    catch {
        Write-Warn "Password change failed (may already be set): $_"
    }

    $authHeader = @{
        "Authorization" = (Get-BasicAuth "admin" $NexusPass)
        "Content-Type"  = "application/json"
    }

    # Helper to create a repository
    function New-NexusRepo {
        param([string]$type, [string]$subtype, [object]$body)
        try {
            $json = $body | ConvertTo-Json -Depth 5
            Invoke-RestMethod `
                -Method POST `
                -Uri "$NexusUrl/service/rest/v1/repositories/$type/$subtype" `
                -Headers $authHeader `
                -Body $json `
                -UseBasicParsing `
                -ErrorAction Stop | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }

    # Maven releases
    $repoCreated = New-NexusRepo -type "maven" -subtype "hosted" -body @{
        name    = "demo-releases"
        online  = $true
        storage = @{ blobStoreName = "default"; strictContentTypeValidation = $true; writePolicy = "allow_once" }
        maven   = @{ versionPolicy = "RELEASE"; layoutPolicy = "STRICT" }
    }
    if ($repoCreated) {
        Write-OK "Nexus: demo-releases repository created."
    }
    else {
        Write-Info "Nexus: demo-releases already exists or creation skipped."
    }

    # Maven snapshots
    $repoCreated = New-NexusRepo -type "maven" -subtype "hosted" -body @{
        name    = "demo-snapshots"
        online  = $true
        storage = @{ blobStoreName = "default"; strictContentTypeValidation = $true; writePolicy = "allow" }
        maven   = @{ versionPolicy = "SNAPSHOT"; layoutPolicy = "STRICT" }
    }
    if ($repoCreated) {
        Write-OK "Nexus: demo-snapshots repository created."
    }
    else {
        Write-Info "Nexus: demo-snapshots already exists or creation skipped."
    }

    # Docker hosted registry
    $repoCreated = New-NexusRepo -type "docker" -subtype "hosted" -body @{
        name    = "demo-docker"
        online  = $true
        storage = @{ blobStoreName = "default"; strictContentTypeValidation = $true; writePolicy = "allow" }
        docker  = @{ v1Enabled = $false; forceBasicAuth = $true; httpPort = 8082 }
    }
    if ($repoCreated) {
        Write-OK "Nexus: demo-docker registry created (port 8082)."
    }
    else {
        Write-Info "Nexus: demo-docker already exists or creation skipped."
    }

    # Enable anonymous access
    try {
        $anonBody = @{ enabled = $true; userId = "anonymous"; realmName = "NexusAuthorizingRealm" } | ConvertTo-Json
        Invoke-RestMethod `
            -Method PUT `
            -Uri "$NexusUrl/service/rest/v1/security/anonymous" `
            -Headers $authHeader `
            -Body $anonBody `
            -UseBasicParsing `
            -ErrorAction Stop | Out-Null
        Write-OK "Nexus: anonymous read access enabled."
    }
    catch {
        Write-Warn "Could not enable anonymous access: $_"
    }

    Write-OK "Nexus provisioning complete."
}

# ---------------------------------------------------------------------------
# Provision GitLab - create project and push demo app
# ---------------------------------------------------------------------------
function Invoke-GitLabSetup {
    Write-Header "Provisioning GitLab"

    Write-Info "Waiting 15 seconds for GitLab to fully initialise..."
    Start-Sleep -Seconds 15

    function Get-BasicAuth64 {
        param([string]$user, [string]$pass)
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("${user}:${pass}")
        return [Convert]::ToBase64String($bytes)
    }

    $authHeader = @{
        "Authorization" = "Basic $(Get-BasicAuth64 'root' $GitLabPass)"
        "Content-Type"  = "application/json"
    }

    # Create project
    Write-Info "Creating GitLab project 'demo-app'..."
    $projectUrl = "$GitLabUrl/root/demo-app.git"
    try {
        $projectBody = @{
            name                   = "demo-app"
            description            = "CI/CD Demo Application - Spring Boot"
            visibility             = "private"
            initialize_with_readme = $false
            default_branch         = "main"
        } | ConvertTo-Json

        $project = Invoke-RestMethod `
            -Method POST `
            -Uri "$GitLabUrl/api/v4/projects" `
            -Headers $authHeader `
            -Body $projectBody `
            -UseBasicParsing `
            -ErrorAction Stop

        $projectUrl = $project.http_url_to_repo
        Write-OK "GitLab project created. ID: $($project.id)"
    }
    catch {
        Write-Warn "Project creation response: $_"
        Write-Info "Project may already exist. Using default URL."
    }

    # Push demo app using git
    Write-Info "Pushing demo application files to GitLab..."
    $tempDir = Join-Path $env:TEMP "cicd-push-$(Get-Random)"

    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Push-Location $tempDir

        # Embed credentials into URL
        $repoWithCreds = $projectUrl -replace "http://", "http://root:$GitLabPass@"

        git init -b main 2>&1 | Out-Null
        git remote add origin $repoWithCreds 2>&1 | Out-Null

        git config user.email "jenkins@cicd.demo" 2>&1 | Out-Null
        git config user.name  "Jenkins Automation" 2>&1 | Out-Null

        # Copy project files
        $scriptDir = $PSScriptRoot
        $filesToCopy = @("app", "Jenkinsfile", "Dockerfile", "chef", "maven-settings.xml")
        foreach ($item in $filesToCopy) {
            $src = Join-Path $scriptDir $item
            if (Test-Path $src) {
                Copy-Item -Recurse -Force $src . 2>$null
                Write-Info "  Copied: $item"
            }
        }

        # Create .gitignore
        @"
target/
.m2/
*.class
*.jar
!app/src/**/*.jar
.DS_Store
.idea/
*.iml
node_modules/
"@ | Set-Content ".gitignore" -Encoding UTF8

        git add -A 2>&1 | Out-Null
        $commitResult = git commit -m "Initial commit - CI/CD demo application" 2>&1
        $pushResult   = git push -u origin main --force 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-OK "Application pushed to GitLab: $projectUrl"
        }
        else {
            Write-Warn "Git push had issues: $pushResult"
        }
    }
    catch {
        Write-Warn "GitLab push failed: $_"
    }
    finally {
        Pop-Location
        if (Test-Path $tempDir) {
            Remove-Item -Recurse -Force $tempDir 2>$null
        }
    }

    # Create webhook
    Write-Info "Creating GitLab webhook to trigger Jenkins..."
    try {
        $hookBody = @{
            url                     = "http://172.20.0.21:8090/project/demo-cicd-pipeline"
            push_events             = $true
            merge_requests_events   = $true
            token                   = "gitlab-webhook-token"
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Method POST `
            -Uri "$GitLabUrl/api/v4/projects/1/hooks" `
            -Headers $authHeader `
            -Body $hookBody `
            -UseBasicParsing `
            -ErrorAction Stop | Out-Null
        Write-OK "GitLab webhook created."
    }
    catch {
        Write-Warn "Webhook creation failed (may already exist): $_"
    }

    Write-OK "GitLab provisioning complete."
}

# ---------------------------------------------------------------------------
# Copy Chef keys from container to host
# ---------------------------------------------------------------------------
function Get-ChefKeys {
    Write-Header "Retrieving Chef Server Keys"

    $keysDir = "chef\keys"
    if (-not (Test-Path $keysDir)) {
        New-Item -ItemType Directory -Path $keysDir -Force | Out-Null
    }

    Write-Info "Copying Chef PEM keys from container..."
    $keyFiles = @("jenkins.pem", "admin.pem", "cicd-demo-validator.pem")
    foreach ($keyFile in $keyFiles) {
        try {
            docker cp "cicd_chef_server:/etc/opscode/keys/$keyFile" "$keysDir\$keyFile" 2>$null
            if (Test-Path "$keysDir\$keyFile") {
                Write-OK "Copied: $keysDir\$keyFile"
            }
        }
        catch {
            Write-Warn "Could not copy $keyFile - Chef Server may still be initialising."
        }
    }
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------
function Show-Summary {
    Write-Host ""
    Write-Host "+==================================================================+" -ForegroundColor Green
    Write-Host "|          CI/CD DEMO ENVIRONMENT IS READY!                       |" -ForegroundColor Green
    Write-Host "+==================================================================+" -ForegroundColor Green
    Write-Host "|  SERVICE URLS                                                    |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  GitLab CE       :  http://localhost:8089                        |" -ForegroundColor Green
    Write-Host "|  Jenkins         :  http://localhost:8090                        |" -ForegroundColor Green
    Write-Host "|  Nexus           :  http://localhost:8081                        |" -ForegroundColor Green
    Write-Host "|  Chef Server     :  http://localhost:8100                        |" -ForegroundColor Green
    Write-Host "|  Chef Supermarket:  http://localhost:8200                        |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  CREDENTIALS                                                     |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  GitLab  :  root       / $GitLabPass                      |" -ForegroundColor Green
    Write-Host "|  Jenkins :  admin      / $JenkinsPass                      |" -ForegroundColor Green
    Write-Host "|  Nexus   :  admin      / $NexusPass                        |" -ForegroundColor Green
    Write-Host "|  Chef    :  admin      / ChefAdmin2024!                         |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  QUICK START                                                     |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  1. Open Jenkins -> Run 'demo-cicd-pipeline'                     |" -ForegroundColor Green
    Write-Host "|  2. Push a code change to GitLab to auto-trigger                 |" -ForegroundColor Green
    Write-Host "|  3. Check Nexus for uploaded JARs and Docker images              |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  MANAGEMENT COMMANDS                                             |" -ForegroundColor Green
    Write-Host "+------------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|  Stop:    docker compose down                                    |" -ForegroundColor Green
    Write-Host "|  Restart: docker compose up -d                                   |" -ForegroundColor Green
    Write-Host "|  Logs:    docker compose logs -f <service>                       |" -ForegroundColor Green
    Write-Host "|  Destroy: docker compose down -v                                 |" -ForegroundColor Green
    Write-Host "+==================================================================+" -ForegroundColor Green
    Write-Host ""
}

# =============================================================================
# Main execution
# =============================================================================
Show-Banner

if ($Help) {
    Write-Host "Usage: .\setup.ps1 [-SkipPull] [-SkipProvision] [-Help]"
    exit 0
}

# Change to script directory so relative paths work
Set-Location $PSScriptRoot

Test-Prerequisites
Test-Resources
Initialize-Directories

if (-not $SkipPull) {
    try {
        Invoke-PullImages
    }
    catch {
        Write-Warn "Image pull step had issues: $_"
    }
}

Start-Services
Wait-ForAllServices

if (-not $SkipProvision) {
    try {
        Invoke-NexusSetup
    }
    catch {
        Write-Warn "Nexus provisioning failed: $_"
    }

    try {
        Invoke-GitLabSetup
    }
    catch {
        Write-Warn "GitLab provisioning failed: $_"
    }

    try {
        Get-ChefKeys
    }
    catch {
        Write-Warn "Chef key retrieval failed: $_"
    }
}

Show-Summary
