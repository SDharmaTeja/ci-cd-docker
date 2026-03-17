// =============================================================================
// 04-jobs.groovy — Create the demo pipeline job pointing to GitLab repo
// =============================================================================
import jenkins.model.*
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.*

def instance = Jenkins.getInstance()

// Only create if it doesn't exist
if (instance.getItem("demo-cicd-pipeline") == null) {
    def job = instance.createProject(WorkflowJob.class, "demo-cicd-pipeline")
    job.setDescription("End-to-end CI/CD demo pipeline: GitLab → Build → Test → Docker → Nexus → Chef → Deploy")

    def scm = new GitSCM("http://172.20.0.20/root/demo-app.git")
    scm.branches = [new BranchSpec("*/main")]
    scm.userRemoteConfigs[0].credentialsId = "gitlab-user-pass"

    def definition = new CpsScmFlowDefinition(scm, "Jenkinsfile")
    definition.setLightweight(true)
    job.setDefinition(definition)
    job.save()

    println "[INIT] Pipeline job 'demo-cicd-pipeline' created."
} else {
    println "[INIT] Pipeline job already exists — skipping."
}

instance.save()
