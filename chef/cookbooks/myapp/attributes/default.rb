# =============================================================================
# attributes/default.rb — Default attributes for myapp cookbook
# =============================================================================

# ---- Application settings --------------------------------------------------
default['myapp']['app_name']     = 'demo-app'
default['myapp']['version']      = '1.0.0-SNAPSHOT'
default['myapp']['port']         = 3000
default['myapp']['install_dir']  = '/opt/demo-app'
default['myapp']['log_dir']      = '/var/log/demo-app'
default['myapp']['user']         = 'appuser'
default['myapp']['group']        = 'appgroup'

# ---- Nexus artifact source -------------------------------------------------
default['myapp']['nexus_url']    = 'http://172.20.0.30:8081'
default['myapp']['nexus_repo']   = 'demo-snapshots'
default['myapp']['group_id']     = 'com.cicd.demo'
default['myapp']['artifact_id']  = 'demo-app'

# ---- Docker settings (alternative deployment) ------------------------------
default['myapp']['use_docker']        = false
default['myapp']['docker_registry']   = '172.20.0.30:8082'
default['myapp']['docker_image']      = 'demo-app'
default['myapp']['docker_tag']        = 'latest'

# ---- Java runtime ----------------------------------------------------------
default['myapp']['java_version']  = '17'
default['myapp']['java_opts']     = '-XX:MaxRAMPercentage=75.0 -XX:+UseContainerSupport'

# ---- Systemd service -------------------------------------------------------
default['myapp']['service_name']  = 'demo-app'
default['myapp']['restart_policy'] = 'on-failure'
