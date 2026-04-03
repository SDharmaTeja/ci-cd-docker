#!/bin/bash

CHEF_SERVER_URL='http://172.31.89.77'
CHEF_ORG='cicd-demo'
CHEF_USER='jenkins'
CHEF_KEY_FILE='/etc/opscode/keys/jenkins.pem'
COOKBOOK_NAME='myapp'
COOKBOOK_VERSION='1.0.0'

cd /opt

git clone https://github.com/SDharmaTeja/ci-cd-docker.git

mkdir -p ~/.chef

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

/opt/opscode/embedded/bin/ruby /opt/opscode/embedded/bin/knife status --config ~/.chef/knife.rb

/opt/opscode/embedded/bin/ruby /opt/opscode/embedded/bin/knife user list --config ~/.chef/knife.rb

cd ci-cd-docker/chef/cookbooks/${COOKBOOK_NAME}

/opt/opscode/embedded/bin/ruby /opt/opscode/embedded/bin/berks install

cat > ~/.berkshelf/config.json <<EOF						
{
  "chef": {
    "chef_server_url": "${CHEF_SERVER_URL}/organizations/${CHEF_ORG}",
	"node_name": "jenkins",
	"client_key": "${CHEF_KEY_FILE}"
  },
  "ssl": {
    "verify": false
  }
}
EOF

/opt/opscode/embedded/bin/ruby /opt/opscode/embedded/bin/knife cookbook list --config ~/.chef/knife.rb

/opt/opscode/embedded/bin/ruby /opt/opscode/embedded/bin/berks upload myapp


/opt/opscode/embedded/bin/ruby /opt/opscode/embedded/bin/knife cookbook list --config ~/.chef/knife.rb
