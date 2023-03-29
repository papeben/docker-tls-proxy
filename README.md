# Docker-TLS-Proxy

A simple docker image for proxying SSL or TLS connections to a TCP or HTTP back-end. Designed to be used as a reverse proxy or kubernetes sidecar container. Simple to configure with environment variables. Uses HAProxy under the hood for lightweight and high-performance operation.

## Getting Started

To get started you'll need to have Docker installed on your local machine. Once you have Docker installed, you can run the proxy with:

```
docker run -p 443:443 -e TARGET_HOST=myserver.local -e TARGET_PORT=9000 papeben/tls-proxy:latest
```

This command will terminate TLS connections on port 443 and forward the unencrypted tunnel to `myserver.local:9000`

A custom SSL certificate can be supplied through a volume. By default `/cert/tls.key` and `/cert/tls.crt` are used.

```
docker run -p 443:443 -e TARGET_HOST=myserver.local -e TARGET_PORT=9000 -v /my/cert/location:/cert papeben/tls-proxy:latest
```

Without a supplied certificate a temporary self-signed SSL server certificate will be generated when the container starts.

## Parameters

Configuration options are laoded from environment variables.

Required parameters:

- **TARGET_HOST** : Target server's IP address or DNS name
- **TARGET_PORT** : Target application's listening TCP port

Optional parameters:

- **LISTEN_PORT** [*443*] : Incoming TLS listening port
- **MAX_CONN** [*4000*] : Maximum simultanious connections
- **TLS_CERT** [*/cert/tls.crt*] : SSL Certificate location
- **TLS_KEY** [*/cert/tls.key*] : Certificate's private key location
- **TLS_MIN_VERSION** [*TLSv1.1*] : Minimum acceptable TLS connection version

## Kubernetes Sidecar

To run this application as a sidecar container in Kubernetes you can use the following YAML configuration as an example.

```
apiVersion: v1
kind: Pod
metadata:
  name: my-generic-web-app
  labels:
    name: my-generic-web-app
spec:
  containers:
  - name: my-generic-web-app
    image: nginx:latest
    ports:
    - containerPort: 80
  - name: tls-proxy
    image: papeben/tls-proxy:latest
    env:
    - name: TARGET_HOST
      value: "127.0.0.1"
    - name: TARGET_PORT
      value: "80"
    ports:
    - containerPort: 443
    volumeMounts:
    - name: my-cert-volume
      mountPath: /cert
  volumes:
    - name: my-cert-volume
      secret:
        secretName: my-tls-cert
---
apiVersion: v1
kind: Service
metadata:
  name: web-app-tls
spec:
  selector:
    name: my-generic-web-app
  ports:
  - name: https
    protocol: TCP
    port: 443
    targetPort: 443
```

In this configuration the first container within the pod is running a default NGINX web server on port 80. The second container runs the papeben/tls-proxy which is configured to forward any connections from port 443 to 127.0.0.1:80, therefore ending up at the NGINX web server.

There is also a volume mounted to the tls-proxy container from the my-tls-cert secret which contains a custom SSL server certificate. This secret can be created with a command such as:

```
kubectl create secret generic my-tls-cert --from-file=tls.key=WebApp.key --from-file=tls.crt=WebApp.crt
```