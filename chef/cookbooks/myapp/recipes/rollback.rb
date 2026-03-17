# =============================================================================
# recipes/rollback.rb — Roll back to previous artifact version
#
# Usage (via knife ssh):
#   knife ssh 'name:node01' 'sudo chef-client --runlist recipe[myapp::rollback]'
# =============================================================================

Chef::Log.warn("=== ROLLBACK triggered for #{node['myapp']['app_name']} ===")

# Derive the previous version (simple patch-level decrement for demo)
current_ver = node['myapp']['version'].dup
if current_ver =~ /(\d+)\.(\d+)\.(\d+)(-.*)?$/
  patch = $3.to_i
  if patch > 0
    prev_version = "#{$1}.#{$2}.#{patch - 1}#{$4}"
  else
    Chef::Log.error('Cannot roll back past patch version 0 — aborting')
    return
  end
else
  Chef::Log.error("Unrecognised version format: #{current_ver}")
  return
end

Chef::Log.warn("Rolling back: #{current_ver} → #{prev_version}")

# Override version attribute and re-run default recipe
node.override['myapp']['version'] = prev_version
include_recipe 'myapp::default'
