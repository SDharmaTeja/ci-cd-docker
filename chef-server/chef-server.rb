# =============================================================================
# chef-server/chef-server.rb
# Chef Server core configuration
# =============================================================================

# Use HTTP for demo (no SSL complexity)
nginx['enable_non_ssl'] = true
nginx['non_ssl_port']   = 80
nginx['ssl_port']       = 443

# Reduce memory usage for demo environment
opscode_erchef['db_pool_size']       = 5
opscode_erchef['max_request_size']   = 2000000
opscode_solr4['heap_size']           = '256m'
opscode_solr4['new_size']            = '64m'
postgresql['shared_buffers']         = '128MB'
postgresql['max_connections']        = 50

# Disable unused components to save resources
dark_launch['actions']               = false
opscode_expander['nodes']            = 1

# License
license['nodes_threshold']           = 25
