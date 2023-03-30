#!/bin/sh
######################################################################
# Docker-TLS-Proxy
# Author: Benjamin Pape
# A simple docker image for proxying SSL or TLS connections to a TCP
# or HTTP back-end. Designed to be used as a reverse proxy or
# kubernetes sidecar container. Simple to configure with environment
# variables. Uses HAProxy under the hood for lightweight
# and high-performance operation.
# Updated 28/03/2023
######################################################################

######################################################################
# HELP MENU
######################################################################
show_help(){
    echo "Some required startup variables are missing.";
    echo "Ensure environment variables are set:";
    echo " - TARGET_HOST: The destination server's IP or DNS name.";
    echo " - TARGET_PORT: The destination server's listening TCP port.";
    exit 1
}

######################################################################
# REQUIRED ENVRONMENT VARIABLES
######################################################################
if [ -z ${TARGET_HOST} ] || [ -z ${TARGET_PORT} ]; then show_help; fi

######################################################################
# DEFAULTS
######################################################################
[ -z ${LISTEN_PORT} ] && LISTEN_PORT=443
[ -z ${MAX_CONN} ] && MAX_CONN=4000
[ -z ${TLS_CERT} ] && TLS_CERT="/cert/tls.crt"
[ -z ${TLS_KEY} ] && TLS_KEY="/cert/tls.key"
[ -z ${TLS_MIN_VERSION} ] && TLS_MIN_VERSION="TLSv1.1"

######################################################################
# CERTIFICATES
######################################################################
if [ ! -f ${TLS_CERT} ] || [ ! -f ${TLS_KEY} ]; then
    echo "TLS Cert and/or Key not found in:"
    echo "${TLS_CERT}"
    echo "${TLS_KEY}"
    echo "Generating temporary certificates for development purposes";
    echo "!!! USE PROPER CERTIFICATES IN PRODUCTION !!!"
    openssl req -new -newkey rsa:2048 -sha256 -days 3650 -nodes -x509 -subj "/O=Development/OU=Container/CN=docker-tls-proxy" -keyout /etc/haproxy/temp.key -out /etc/haproxy/temp.crt -addext "subjectAltName=DNS:docker-tls-proxy.local,DNS:docker-tls-proxy" -addext "extendedKeyUsage=serverAuth" -addext "keyUsage=critical, digitalSignature, nonRepudiation" &> /dev/null
    cat /etc/haproxy/temp.key /etc/haproxy/temp.crt >> /etc/haproxy/fullchain.pem
else
    echo "Certificates found in ${TLS_CERT} and ${TLS_KEY}"
    cat "${TLS_CERT}" "${TLS_KEY}" >> /etc/haproxy/fullchain.pem
fi

######################################################################
# HAPROXY CONFIGURATION
######################################################################

echo """
global
    log stdout format raw local0
    pidfile /var/run/haproxy.pid
    maxconn ${MAX_CONN}
    user haproxy
    group haproxy
    ssl-default-bind-options no-tls-tickets ssl-min-ver ${TLS_MIN_VERSION}
    ssl-default-bind-ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA
defaults
    mode tcp
    log global
    option redispatch
    option tcplog
    retries 3
    timeout queue 30s
    timeout connect 30s
    timeout client 1m
    timeout server 10s
    timeout check 5s

frontend TLS_IN
    bind *:${LISTEN_PORT} ssl crt /etc/haproxy/fullchain.pem
    default_backend TCP_OUT
    option tcplog
    log global

backend TCP_OUT
    balance roundrobin
    server target ${TARGET_HOST}:${TARGET_PORT} check
    log global
""" > /etc/haproxy/haproxy.cfg



echo "###########################################################"
echo "Starting SSL Termination from:"
echo "Port ${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}"
echo "###########################################################"

######################################################################
# STARTUP
######################################################################

haproxy -f /etc/haproxy/haproxy.cfg


