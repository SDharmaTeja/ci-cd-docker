name             'myapp'
maintainer       'CI/CD Demo'
maintainer_email 'devops@cicd.demo'
license          'Apache-2.0'
description      'Deploys the demo-app Spring Boot application'
version          '1.0.0'
chef_version     '>= 16.0'

# Supported platforms
supports 'ubuntu', '>= 20.04'
supports 'centos', '>= 8.0'
supports 'rhel',   '>= 8.0'

# Dependencies from Supermarket
depends 'java',   '~> 10.0'
depends 'docker', '~> 10.0'
