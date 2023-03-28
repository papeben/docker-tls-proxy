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
    echo " - TARGET_HOST: The backend server's IP or hostname.";
    echo " - TARGET_PORT: The backend server's listening TCP port.";
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

######################################################################
# CERTIFICATES
######################################################################
if [ ! -f /cert/tls.crt ] || [ ! -f /cert/tls.key ]; then
    echo "TLS Cert and/or Key not found in:"
    echo "/cert/tls.key"
    echo "/cert/tls.crt"
    echo "Generating temporary certificates for development purposes";
    echo "!!! DO NOT USE THIS IN PRODUCTION !!!"
    openssl req -new -newkey rsa:2048 -sha256 -days 3650 -nodes -x509 -subj "/O=Development/OU=Container/CN=docker-tls-proxy" -keyout /etc/haproxy/temp.key -out /etc/haproxy/temp.crt -addext "subjectAltName=DNS:docker-tls-proxy.local,DNS:docker-tls-proxy" -addext "extendedKeyUsage=serverAuth" -addext "keyUsage=critical, digitalSignature, nonRepudiation"
    cat /etc/haproxy/temp.key /etc/haproxy/temp.crt >> /etc/haproxy/fullchain.pem
else
    echo "Certificates found in /cert/tls.key and /cert/tls.crt"
    cat /cert/tls.key /cert/tls.crt >> /etc/haproxy/fullchain.pem
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


