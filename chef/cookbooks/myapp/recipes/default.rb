# =============================================================================
# recipes/default.rb — Main deployment recipe for demo-app
#
# Execution order:
#   1. Ensure Java is installed
#   2. Create app user, group, and directories
#   3. Download JAR from Nexus
#   4. Deploy systemd service unit
#   5. Start / restart service
# =============================================================================

Chef::Log.info("=== myapp cookbook v#{cookbook_version} ===")
Chef::Log.info("Deploying #{node['myapp']['app_name']} v#{node['myapp']['version']}")

# ---- 1. Java runtime -------------------------------------------------------
# Uses the 'java' community cookbook from Supermarket
include_recipe 'java::default' if node['myapp']['java_version']

# ---- 2. System user & group -----------------------------------------------
group node['myapp']['group'] do
  system true
  action :create
end

user node['myapp']['user'] do
  gid     node['myapp']['group']
  system  true
  shell   '/bin/false'
  home    node['myapp']['install_dir']
  action  :create
end

# ---- 3. Directories --------------------------------------------------------
[node['myapp']['install_dir'], node['myapp']['log_dir']].each do |dir|
  directory dir do
    owner     node['myapp']['user']
    group     node['myapp']['group']
    mode      '0755'
    recursive true
    action    :create
  end
end

# ---- 4. Download JAR from Nexus -------------------------------------------
artifact_filename = "#{node['myapp']['artifact_id']}-#{node['myapp']['version']}.jar"
artifact_path     = "#{node['myapp']['install_dir']}/#{node['myapp']['app_name']}.jar"

nexus_artifact_url = [
  node['myapp']['nexus_url'],
  'repository',
  node['myapp']['nexus_repo'],
  node['myapp']['group_id'].tr('.', '/'),
  node['myapp']['artifact_id'],
  node['myapp']['version'],
  artifact_filename
].join('/')

remote_file artifact_path do
  source   nexus_artifact_url
  owner    node['myapp']['user']
  group    node['myapp']['group']
  mode     '0755'
  # Nexus credentials via data bag (optional)
  # headers({ 'Authorization' => "Basic #{Base64.encode64('admin:NexusDemo2024!').chomp}" })
  notifies :restart, "service[#{node['myapp']['service_name']}]", :delayed
  action   :create
end

# ---- 5. Environment file ---------------------------------------------------
template "#{node['myapp']['install_dir']}/app.env" do
  source 'app.env.erb'
  owner  node['myapp']['user']
  group  node['myapp']['group']
  mode   '0640'
  variables(
    port:      node['myapp']['port'],
    java_opts: node['myapp']['java_opts'],
    version:   node['myapp']['version']
  )
  notifies :restart, "service[#{node['myapp']['service_name']}]", :delayed
end

# ---- 6. Systemd service unit -----------------------------------------------
template "/etc/systemd/system/#{node['myapp']['service_name']}.service" do
  source 'demo-app.service.erb'
  owner  'root'
  group  'root'
  mode   '0644'
  variables(
    app_name:    node['myapp']['app_name'],
    install_dir: node['myapp']['install_dir'],
    log_dir:     node['myapp']['log_dir'],
    user:        node['myapp']['user'],
    group:       node['myapp']['group'],
    port:        node['myapp']['port'],
    java_opts:   node['myapp']['java_opts'],
    restart:     node['myapp']['restart_policy']
  )
  notifies :run,     'execute[systemd-reload]', :immediately
  notifies :restart, "service[#{node['myapp']['service_name']}]", :delayed
end

execute 'systemd-reload' do
  command 'systemctl daemon-reload'
  action  :nothing
end

# ---- 7. Enable & start service ---------------------------------------------
service node['myapp']['service_name'] do
  provider Chef::Provider::Service::Systemd
  supports status: true, restart: true, reload: true
  action   [:enable, :start]
end

# ---- 8. Optional: firewall rule (port 3000) --------------------------------
# Uncomment if using the firewall cookbook
# firewall_rule 'demo-app' do
#   port      node['myapp']['port']
#   protocol  :tcp
#   action    :allow
# end

Chef::Log.info("=== Deployment complete: #{node['myapp']['app_name']} on port #{node['myapp']['port']} ===")
