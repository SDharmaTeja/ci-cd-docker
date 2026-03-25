#!/bin/bash
chown -R gitlab-psql:gitlab-psql /var/opt/gitlab/postgresql
gitlab-ctl restart postgresql
gitlab-ctl restart
