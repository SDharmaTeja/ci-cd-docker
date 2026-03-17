// =============================================================================
// 02-credentials.groovy — Pre-configure credentials for GitLab, Nexus & Chef
// =============================================================================
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import com.cloudbees.jenkins.plugins.sshcredentials.impl.*
import hudson.util.Secret
import org.jenkinsci.plugins.plaincredentials.impl.*

def instance   = Jenkins.getInstance()
def domain     = Domain.global()
def store      = instance.getExtensionList(
                   'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
                 )[0].getStore()

// ---- GitLab personal access token ----
def gitlabToken = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "gitlab-token",
    "GitLab API Token",
    Secret.fromString("glpat-demo-token-replace-me")
)
store.addCredentials(domain, gitlabToken)

// ---- GitLab username/password (for git clone over HTTP) ----
def gitlabUser = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "gitlab-user-pass",
    "GitLab root credentials",
    "root",
    "CicdDemo2024!"
)
store.addCredentials(domain, gitlabUser)

// ---- Nexus username/password ----
def nexusCreds = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "nexus-user-pass",
    "Nexus admin credentials",
    "admin",
    "NexusDemo2024!"
)
store.addCredentials(domain, nexusCreds)

// ---- Chef Server private key (placeholder) ----
def chefPem = new FileCredentialsImpl(
    CredentialsScope.GLOBAL,
    "chef-client-key",
    "Chef client private key (jenkins.pem)",
    "jenkins.pem",
    SecretBytes.fromBytes("# Replace with real chef PEM key".getBytes())
)
store.addCredentials(domain, chefPem)

// ---- Docker registry (Nexus hosted Docker) ----
def dockerCreds = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL,
    "docker-registry",
    "Docker registry (Nexus)",
    "admin",
    "NexusDemo2024!"
)
store.addCredentials(domain, dockerCreds)

instance.save()
println "[INIT] Credentials configured."
