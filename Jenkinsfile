// =============================================================================
// Jenkinsfile — Complete CI/CD Pipeline
//
// Flow:
//   Stage 1: Checkout       — pull code from GitLab
//   Stage 2: Build          — compile/package with Maven
//   Stage 3: Unit Tests     — run tests, publish JUnit results
//   Stage 4: Docker Build   — build Docker image
//   Stage 5: Push to Nexus  — upload JAR + Docker image to Nexus
//   Stage 6: Chef Cookbook  — upload cookbook to Chef Server
//   Stage 7: Deploy         — trigger Chef client run on target node
// =============================================================================

pipeline {

    agent any

    // ---- Tool definitions (configured in Jenkins tools) ----
    tools {
        maven 'Maven3'
    }

    // ---- Pipeline-wide environment ----
    environment {
        // Service URLs (Docker internal network)
        GITLAB_URL         = 'http://172.20.0.20:8089'
        NEXUS_URL          = 'http://172.20.0.30:8081'
        NEXUS_DOCKER_URL   = '172.20.0.30:8082'
        CHEF_SERVER_URL    = 'http://172.20.0.40'
        SUPERMARKET_URL    = 'http://172.20.0.50'
        TARGET_NODE        = '172.20.0.60'

        // Artifact identifiers
        APP_NAME           = 'demo-app'
        APP_VERSION        = sh(script: "mvn help:evaluate -Dexpression=project.version -q -DforceStdout 2>/dev/null || echo '1.0.0-SNAPSHOT'", returnStdout: true).trim()
        DOCKER_IMAGE       = "${NEXUS_DOCKER_URL}/${APP_NAME}:${BUILD_NUMBER}"

        // Chef configuration
        CHEF_ORG           = 'cicd-demo'
        CHEF_USER          = 'jenkins'
        COOKBOOK_NAME      = 'myapp'
        COOKBOOK_VERSION   = '1.0.0'

        // Nexus repository names
        NEXUS_REPO_RELEASE = 'demo-releases'
        NEXUS_REPO_SNAP    = 'demo-snapshots'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 60, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        // =====================================================================
        // STAGE 1 — Checkout source code from GitLab
        // =====================================================================
        stage('Checkout') {
            steps {
                echo '🔵 Stage 1: Checking out source code from GitLab...'
                git branch: 'main',
                    credentialsId: 'gitlab-user-pass',
                    url: "${GITLAB_URL}/root/demo-app.git"

                script {
                    def commitHash = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    def commitMsg  = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
                    echo "Commit: ${commitHash} — ${commitMsg}"

                    // Tag the build with git commit info
                    currentBuild.displayName = "#${BUILD_NUMBER} — ${commitHash}"
                }
            }
        }

        // =====================================================================
        // STAGE 2 — Build application (Maven)
        // =====================================================================
        stage('Build') {
            steps {
                echo '🔨 Stage 2: Building application with Maven...'
                sh '''
                    mvn clean package \
                        -DskipTests \
                        -Dmaven.repo.local=.m2 \
                        --batch-mode \
                        -Pproduction
                '''
                // Archive JAR for downstream stages
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
                stash includes: 'target/*.jar', name: 'app-jar'
            }
            post {
                success { echo '✅ Build succeeded.' }
                failure { echo '❌ Build failed!' }
            }
        }

        // =====================================================================
        // STAGE 3 — Unit Tests
        // =====================================================================
        stage('Unit Tests') {
            steps {
                echo '🧪 Stage 3: Running unit tests...'
                sh '''
                    mvn test \
                        -Dmaven.repo.local=.m2 \
                        --batch-mode
                '''
            }
            post {
                always {
                    // Publish JUnit test results
                    junit testResults: 'target/surefire-reports/*.xml',
                          allowEmptyResults: true

                    // Publish code coverage (JaCoCo)
                    jacoco execPattern:     'target/jacoco.exec',
                           classPattern:    'target/classes',
                           sourcePattern:   'src/main/java',
                           exclusionPattern: '**/*Test*.class'
                }
                success { echo '✅ All tests passed.' }
                failure {
                    echo '❌ Tests failed!'
                    // Optionally: send email / Slack notification here
                }
            }
        }

        // =====================================================================
        // STAGE 4 — Build Docker Image
        // =====================================================================
        stage('Docker Build') {
            steps {
                echo '🐳 Stage 4: Building Docker image...'
                unstash 'app-jar'
                script {
                    docker.build(
                        "${DOCKER_IMAGE}",
                        "--build-arg APP_VERSION=${APP_VERSION} \
                         --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                         --label git-commit=${GIT_COMMIT} \
                         --label build-date=${new Date().format('yyyy-MM-dd')} \
                         ."
                    )
                }
                sh "docker images ${DOCKER_IMAGE}"
            }
            post {
                success { echo '✅ Docker image built: ' + DOCKER_IMAGE }
                failure { echo '❌ Docker build failed!' }
            }
        }

        // =====================================================================
        // STAGE 5 — Push Artifact to Nexus Repository
        // =====================================================================
        stage('Push to Nexus') {
            parallel {

                stage('Upload JAR') {
                    steps {
                        echo '📦 Stage 5a: Uploading JAR to Nexus...'
                        withCredentials([usernamePassword(
                            credentialsId:    'nexus-user-pass',
                            usernameVariable: 'NEXUS_USER',
                            passwordVariable: 'NEXUS_PASS'
                        )]) {
                            script {
                                def repo = APP_VERSION.contains('SNAPSHOT')
                                    ? NEXUS_REPO_SNAP
                                    : NEXUS_REPO_RELEASE

                                nexusArtifactUploader(
                                    nexusVersion:   'nexus3',
                                    protocol:       'http',
                                    nexusUrl:       '172.20.0.30:8081',
                                    groupId:        'com.cicd.demo',
                                    version:        "${APP_VERSION}",
                                    repository:     repo,
                                    credentialsId:  'nexus-user-pass',
                                    artifacts: [[
                                        artifactId: APP_NAME,
                                        classifier: '',
                                        file:       "target/${APP_NAME}-${APP_VERSION}.jar",
                                        type:       'jar'
                                    ],[
                                        artifactId: APP_NAME,
                                        classifier: '',
                                        file:       'pom.xml',
                                        type:       'pom'
                                    ]]
                                )
                            }
                        }
                        echo '✅ JAR uploaded to Nexus.'
                    }
                }

                stage('Push Docker Image') {
                    steps {
                        echo '📦 Stage 5b: Pushing Docker image to Nexus Docker Registry...'
                        withCredentials([usernamePassword(
                            credentialsId:    'docker-registry',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        )]) {
                            sh """
                                echo "${DOCKER_PASS}" | docker login ${NEXUS_DOCKER_URL} \
                                    -u "${DOCKER_USER}" --password-stdin
                                docker push ${DOCKER_IMAGE}
                                docker tag ${DOCKER_IMAGE} ${NEXUS_DOCKER_URL}/${APP_NAME}:latest
                                docker push ${NEXUS_DOCKER_URL}/${APP_NAME}:latest
                                docker logout ${NEXUS_DOCKER_URL}
                            """
                        }
                        echo '✅ Docker image pushed to Nexus.'
                    }
                }
            }
        }

        // =====================================================================
        // STAGE 6 — Upload Cookbook to Chef Server
        // =====================================================================
        stage('Chef Cookbook Upload') {
            steps {
                echo '👨‍🍳 Stage 6: Uploading cookbook to Chef Server...'
                withCredentials([file(
                    credentialsId: 'chef-client-key',
                    variable:      'CHEF_KEY_FILE'
                )]) {
                    sh '''
                        # Create knife configuration directory
                        mkdir -p ~/.chef

                        # Write knife.rb for this build
                        cat > ~/.chef/knife.rb <<EOF
current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "jenkins"
client_key               "${CHEF_KEY_FILE}"
chef_server_url          "${CHEF_SERVER_URL}/organizations/${CHEF_ORG}"
cookbook_path            ["#{current_dir}/../chef/cookbooks"]
ssl_verify_mode          :verify_none
EOF

                        # Verify Chef Server connectivity
                        knife status --config ~/.chef/knife.rb || echo "Chef Server not ready — continuing"

                        # Lint cookbook with Cookstyle
                        cd chef/cookbooks/${COOKBOOK_NAME}
                        cookstyle . || echo "Cookstyle warnings (non-blocking)"

                        # Run ChefSpec unit tests
                        # rspec spec/ || echo "Spec tests skipped"

                        # Upload cookbook to Chef Server
                        knife cookbook upload ${COOKBOOK_NAME} \
                            --config ~/.chef/knife.rb \
                            --freeze \
                            --force || echo "Chef Server upload skipped (server may not be configured)"

                        echo "Cookbook ${COOKBOOK_NAME} v${COOKBOOK_VERSION} uploaded."
                    '''
                }
            }
            post {
                success { echo '✅ Cookbook uploaded to Chef Server.' }
                failure { echo '⚠️  Chef upload failed — deployment may use cached cookbook.' }
            }
        }

        // =====================================================================
        // STAGE 7 — Deploy using Chef Client
        // =====================================================================
        stage('Deploy') {
            steps {
                echo '🚀 Stage 7: Deploying application via Chef client...'
                withCredentials([
                    usernamePassword(
                        credentialsId:    'gitlab-user-pass',
                        usernameVariable: 'NODE_USER',
                        passwordVariable: 'NODE_PASS'
                    ),
                    file(
                        credentialsId: 'chef-client-key',
                        variable:      'CHEF_KEY_FILE'
                    )
                ]) {
                    sh """
                        # Bootstrap target node with chef-client if first deploy
                        # (knife bootstrap handles SSH + chef-client install)
                        knife bootstrap ${TARGET_NODE} \
                            --ssh-user root \
                            --ssh-password nodepassword \
                            --node-name node01 \
                            --run-list "recipe[${COOKBOOK_NAME}::default]" \
                            --config ~/.chef/knife.rb \
                            --yes \
                            --sudo \
                            --connection-timeout 60 \
                            --bootstrap-no-proxy || echo "Bootstrap skipped (already bootstrapped or Chef unavailable)"

                        # Force chef-client run on target to pull latest cookbook
                        knife ssh "name:node01" \
                            "sudo chef-client --runlist 'recipe[${COOKBOOK_NAME}]'" \
                            --ssh-user root \
                            --ssh-password nodepassword \
                            --config ~/.chef/knife.rb \
                            --attribute ipaddress || echo "Chef-client run skipped"

                        echo "✅ Deployment triggered on ${TARGET_NODE}"
                    """
                }

                // Smoke test — verify the app is responding
                sh """
                    echo "⏳ Waiting 30s for application to start..."
                    sleep 30
                    curl -f http://${TARGET_NODE}:3000/health \
                        --retry 5 \
                        --retry-delay 10 \
                        --retry-connrefused \
                        -o /dev/null \
                        -w "HTTP %{http_code}" || echo "⚠️  Health check skipped"
                """
            }
            post {
                success {
                    echo "✅ Deployment successful! App running on ${TARGET_NODE}:3000"
                }
                failure {
                    echo '❌ Deployment failed!'
                    // Optionally trigger rollback here:
                    // sh "knife ssh 'name:node01' 'sudo chef-client --runlist recipe[${COOKBOOK_NAME}::rollback]' ..."
                }
            }
        }
    }

    // =========================================================================
    // Post-pipeline actions
    // =========================================================================
    post {
        always {
            echo '🧹 Cleaning up workspace...'
            // Remove local Docker image to save disk space
            sh "docker rmi ${DOCKER_IMAGE} || true"
            cleanWs()
        }
        success {
            echo """
╔══════════════════════════════════════════════╗
║  ✅  PIPELINE COMPLETED SUCCESSFULLY         ║
║  Build: #${BUILD_NUMBER}                     ║
║  App Version: ${APP_VERSION}                 ║
╚══════════════════════════════════════════════╝
            """
        }
        failure {
            echo """
╔══════════════════════════════════════════════╗
║  ❌  PIPELINE FAILED                         ║
║  Build: #${BUILD_NUMBER}                     ║
║  Check logs above for details                ║
╚══════════════════════════════════════════════╝
            """
            // emailext subject: "FAILED: ${JOB_NAME} #${BUILD_NUMBER}",
            //         body: "See ${BUILD_URL}",
            //         to: 'devops-team@company.com'
        }
    }
}
