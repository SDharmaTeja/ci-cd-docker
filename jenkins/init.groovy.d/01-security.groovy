// =============================================================================
// 01-security.groovy — Configure Jenkins security & admin user
// Runs automatically on Jenkins startup
// =============================================================================
import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.getInstance()

// ---- Create admin user ----
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "CicdDemo2024!")
hudsonRealm.createAccount("developer", "Developer2024!")
instance.setSecurityRealm(hudsonRealm)

// ---- Authorization strategy: admin has full access ----
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// ---- Allow agent-to-master connections ----
instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)

// ---- Set Jenkins URL ----
def jlc = JenkinsLocationConfiguration.get()
jlc.setUrl("http://localhost:8090/")
jlc.save()

instance.save()
println "[INIT] Security configured — admin / CicdDemo2024!"
