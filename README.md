# CI/CD Demo Environment

A self-contained CI/CD pipeline demo using Docker Compose.

```
Developer → GitLab → Jenkins → Nexus → Chef Server → Target Node
```

## Services

| Service | URL | Credentials |
|---|---|---|
| GitLab CE | http://localhost:8080 | root / CicdDemo2024! |
| Jenkins | http://localhost:8090 | admin / CicdDemo2024! |
| Nexus | http://localhost:8081 | admin / NexusDemo2024! |
| Chef Server | http://localhost:8100 | admin / ChefAdmin2024! |
| Chef Supermarket | http://localhost:8200 | — |
| Target Node (SSH) | localhost:2200 | root / nodepassword |

## Quick Start

**Linux/macOS:**
```bash
chmod +x setup.sh
./setup.sh
```

**Windows (PowerShell as Admin):**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
.\setup.ps1
```

**Manual start:**
```bash
docker compose up -d
```

## System Requirements

- Docker Desktop (or Docker Engine + Compose plugin)
- 8 GB RAM minimum (16 GB recommended)
- 20 GB free disk
- Ports: 8080, 8081, 8082, 8090, 8100, 8200, 2200, 2222, 50000

## Pipeline Stages

```
Stage 1: Checkout      → git clone from GitLab
Stage 2: Build         → mvn package (Spring Boot JAR)
Stage 3: Unit Tests    → mvn test + JUnit/JaCoCo reports
Stage 4: Docker Build  → docker build (multi-stage)
Stage 5: Push to Nexus → JAR → demo-snapshots, Image → demo-docker
Stage 6: Chef Upload   → knife cookbook upload myapp
Stage 7: Deploy        → knife bootstrap + chef-client run
```

## Project Structure

```
cicd-demo/
├── docker-compose.yml          # All 7 services
├── Dockerfile                  # Demo app multi-stage build
├── Jenkinsfile                 # 7-stage pipeline
├── setup.sh                    # Linux/macOS setup
├── setup.ps1                   # Windows setup
├── app/                        # Spring Boot application
│   ├── pom.xml
│   ├── .gitlab-ci.yml
│   └── src/
│       ├── main/java/com/cicd/demo/
│       │   ├── DemoApplication.java
│       │   ├── AppController.java
│       │   └── GreetingService.java
│       └── test/java/com/cicd/demo/
│           └── DemoApplicationTests.java
├── jenkins/
│   ├── Dockerfile              # Jenkins + plugins + Chef workstation
│   ├── plugins.txt             # Pre-installed plugins list
│   └── init.groovy.d/          # Auto-configuration scripts
│       ├── 01-security.groovy
│       ├── 02-credentials.groovy
│       ├── 03-tools.groovy
│       └── 04-jobs.groovy
├── chef/
│   ├── knife.rb                # Knife configuration
│   ├── setup-chef-server.sh   # Chef Server bootstrap
│   └── cookbooks/myapp/
│       ├── metadata.rb
│       ├── attributes/default.rb
│       ├── recipes/
│       │   ├── default.rb      # Install + deploy app
│       │   └── rollback.rb     # Roll back to previous version
│       └── templates/default/
│           ├── demo-app.service.erb
│           └── app.env.erb
├── nexus/
│   └── setup-nexus.sh         # Create repositories via REST API
├── gitlab/
│   └── setup-gitlab.sh        # Create project + push app
└── postgres/
    └── init-multiple-dbs.sh   # Create multiple databases
```

## Network Architecture

```
┌─────────────────────────── Docker Network: 172.20.0.0/24 ──────────────────────────────┐
│                                                                                          │
│  .10 PostgreSQL        .11 Redis          .20 GitLab CE        .21 Jenkins              │
│  ┌─────────────┐      ┌─────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │  postgres   │◄─────│    redis    │    │  gitlab-ce   │◄───│   jenkins    │          │
│  │   :5432     │      │    :6379    │    │  :8080/:2222 │    │   :8090      │          │
│  └─────────────┘      └─────────────┘    └──────┬───────┘    └──────┬───────┘          │
│         ▲                    ▲                   │ push              │ trigger           │
│         │                    │                   ▼                   ▼                   │
│  .50 Supermarket       .40 Chef Server    .30 Nexus           .60 Target Node           │
│  ┌─────────────┐      ┌─────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ supermarket │◄─────│ chef-server │◄───│    nexus     │    │  ubuntu:22   │          │
│  │   :8200     │      │  :8100/8143 │    │ :8081/:8082  │    │  (SSH :22)   │          │
│  └─────────────┘      └─────────────┘    └──────────────┘    └──────────────┘          │
│                                                                                          │
└──────────────────────────────────────────────────────────────────────────────────────────┘

Host port mappings:
  8080 → GitLab HTTP       8081 → Nexus UI        8082 → Nexus Docker
  8090 → Jenkins           8100 → Chef Server     8200 → Supermarket
  2222 → GitLab SSH        2200 → Target SSH      50000 → Jenkins agent
```

## Management Commands

```bash
# View all container status
docker compose ps

# Follow logs for a specific service
docker compose logs -f jenkins
docker compose logs -f gitlab

# Restart a single service
docker compose restart jenkins

# Stop everything (keep data)
docker compose down

# Nuclear option — destroy all volumes/data
docker compose down -v

# Shell into a container
docker exec -it cicd_jenkins bash
docker exec -it cicd_gitlab bash
docker exec -it cicd_nexus bash
```

## Triggering the Pipeline

### Option 1: Manual trigger (Jenkins UI)
1. Open http://localhost:8090
2. Log in as `admin / CicdDemo2024!`
3. Click `demo-cicd-pipeline`
4. Click `Build Now`

### Option 2: Git push (automatic webhook)
```bash
git clone http://localhost:8080/root/demo-app.git
cd demo-app
echo "// change" >> app/src/main/java/com/cicd/demo/GreetingService.java
git add -A && git commit -m "trigger pipeline"
git push
```

### Option 3: curl (API trigger)
```bash
curl -X POST http://localhost:8090/job/demo-cicd-pipeline/build \
  --user admin:CicdDemo2024!
```

## Uploading Cookbook to Chef Server Manually

```bash
# Install Chef Workstation on your host
# https://docs.chef.io/workstation/install_workstation/

# Configure knife
cp chef/knife.rb ~/.chef/knife.rb
cp chef/keys/jenkins.pem ~/.chef/

# Verify Chef Server connection
knife status

# Upload cookbook
knife cookbook upload myapp --cookbook-path chef/cookbooks

# Bootstrap a node
knife bootstrap 172.20.0.60 \
  --ssh-user root --ssh-password nodepassword \
  --node-name node01 \
  --run-list "recipe[myapp::default]"

# Run chef-client on node
knife ssh "name:node01" "sudo chef-client" --ssh-user root --ssh-password nodepassword
```

## Uploading Artifacts to Nexus Manually

```bash
# Upload JAR via curl
curl -u admin:NexusDemo2024! \
  --upload-file target/demo-app-1.0.0-SNAPSHOT.jar \
  "http://localhost:8081/repository/demo-snapshots/com/cicd/demo/demo-app/1.0.0-SNAPSHOT/demo-app-1.0.0-SNAPSHOT.jar"

# Upload via Maven
mvn deploy -DskipTests \
  -DaltDeploymentRepository=nexus::default::http://localhost:8081/repository/demo-snapshots

# Push Docker image to Nexus registry
docker login localhost:8082 -u admin -p NexusDemo2024!
docker tag myapp:latest localhost:8082/demo-app:latest
docker push localhost:8082/demo-app:latest
```

## Troubleshooting

**GitLab takes too long to start:**
GitLab CE needs 3-5 minutes on first start. Run `docker compose logs -f gitlab` to monitor.

**Jenkins can't connect to GitLab:**
Ensure the GitLab PAT was created. In Jenkins → Manage Credentials → update `gitlab-token`.

**Chef Server won't start:**
Chef Server requires privileged containers and ~2GB RAM. Check:
```bash
docker compose logs chef-server
docker stats cicd_chef_server
```

**Nexus "admin.password" not found:**
Nexus 3.17+ uses a random initial password. The setup script reads it from the container.
If it fails, run: `docker exec cicd_nexus cat /nexus-data/admin.password`

**Port conflicts:**
Edit `docker-compose.yml` to change host-side port mappings (left side of `host:container`).
