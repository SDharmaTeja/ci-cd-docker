// =============================================================================
// 03-tools.groovy — Configure Maven, NodeJS, Docker tool installations
// =============================================================================
import jenkins.model.*
import hudson.tasks.Maven
import hudson.tasks.Maven.MavenInstallation
import hudson.tools.*

def instance = Jenkins.getInstance()

// ---- Maven ----
def mavenDesc = instance.getDescriptor(Maven.class) as Maven.DescriptorImpl
def mavenInstaller = new Maven.MavenInstallation(
    "Maven3",
    "",
    [new InstallSourceProperty([new MavenInstaller("3.9.6")])]
)
mavenDesc.setInstallations(mavenInstaller)
mavenDesc.save()

println "[INIT] Tools configured (Maven 3.9.6)."
instance.save()
