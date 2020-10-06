# Dockerfile for generating the UMD Web Application static files Docker image
#
# To build:
#
# docker build -t docker.lib.umd.edu/umd-web-app-static-files:<VERSION> -f Dockerfile .
#
# where <VERSION> is the Docker image version to create.
FROM nginx:1.19.2

COPY docker_config/nginx/ /etc/nginx/

COPY static-files /usr/share/nginx/html

