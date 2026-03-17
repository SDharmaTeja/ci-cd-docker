# =============================================================================
# chef-supermarket/Dockerfile
# Lightweight Chef Supermarket substitute for demo purposes.
# Uses Gitea (lightweight Git service) as an internal cookbook browser,
# OR a simple Nginx-based cookbook file server.
#
# WHY: The official chef/supermarket image is not publicly available.
# For a CI/CD demo, what we need is:
#   1. A place to browse/download cookbooks  ← Nginx file server
#   2. knife supermarket to resolve deps     ← points to supermarket.chef.io
#
# This image serves an internal cookbook registry over HTTP.
# =============================================================================

FROM nginx:1.25-alpine

RUN apk add --no-cache curl bash

# Create cookbook storage directory
RUN mkdir -p /usr/share/nginx/cookbooks /usr/share/nginx/html/api/v1

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY supermarket-ui/index.html /usr/share/nginx/html/index.html

# Copy API stub responses
COPY api/universe.json /usr/share/nginx/html/api/v1/universe
COPY api/status.json   /usr/share/nginx/html/api/v1/status

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost/api/v1/status || exit 1

CMD ["nginx", "-g", "daemon off;"]
