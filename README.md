# UMD Web Static Files

Respository for creating a Docker image that holds default versions of commonly
used "static files" for web applications, such as:

* favicon.ico
* robots.txt
* sitemap.xml

The Docker image uses a simple Nginx-based container, providing a generic
mechanism for accessing these files in a Kubernetes stack.

The "robots.txt" and "sitemap.xml" files are "default closed", i.e., the
"robots.txt" does not allow crawling, and the "sitemap.xml" is empty.

The files are set up in such a way that a Kubernetes overlay can override each
file individually.

## Repository Files

### Dockerfile

The "Dockerfile" is used to build the Docker image.

```
> docker build -t docker.lib.umd.edu/umd-web-app-static-files:<VERSION> -f Dockerfile .
```

where \<VERSION> is the Docker image version to create.

The resulting Docker image should then be pushed to the Nexus.

### docker_config/nginx/

Contains the configuration for the Nginx server.

### static-files/

This directory contains a subdirectory for each file being served. The files
are organized in this manner, so that the files can be overridden indvidually
by a Kubernetes configuration.

## Kubernetes Configuration

The following is an example of using the "umd-web-app-static-files" image in
a Kubernetes configuration following the layout in
["k8s-new-app"](https://github.com/umd-lib/k8s-new-app).

In the following examples, the name of the application is "foobar". The files
will be served at the following URLs:

* https://foobar.lib.umd.edu/favicon.ico
* https://foobar.lib.umd.edu/robots.txt
* https://foobar.lib.umd.edu/sitemap.xml

## Changes to the "base" overlay

The "base" overlay sets up the "foobar-static-files" pod running the
"umd-web-static-files" image.

### base/deployment.yaml

The following creates a "foobar-static-files" Deployment, with an associated "foobar-static-files" pod.

The deployment uses the "umd-web-static-files" Nginx Docker image
(docker.lib.umd.edu/umd-web-app-static-files:latest), which serves a default set
of files from the "/usr/share/nginx/html" directory. Each file is in it's own
subdirectory, so it can be overridden by the overlays:

* favicon/favicon.ico
* robots/robots.txt
* sitemap/sitemap.xml

The liveness/readiness probes use the "robots.txt" file for determining pod status.

```
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: foobar-static-files
  labels: &foobar-static-files-labels
    app: foobar-static-files
    app.kubernetes.io/instance: foobar
    app.kubernetes.io/name: static-files
    app.kubernetes.io/component: static-files
spec:
  # Configure replication factor for the pod, if more than one
  replicas: 1

  # To link the pod to deployment
  selector:
    matchLabels:
      app: foobar-static-files

  template:
    # Metadata for the Pod template
    metadata:
      # Labels for the pod
      labels: &foobar-static-files-labels
        app: foobar-static-files
    spec:
      imagePullSecrets:
        - name: regcred
      # Container Configuration
      containers:
      - image: docker.lib.umd.edu/umd-web-app-static-files:latest
        name: foobar-static-files
        # Resource configuration
        resources:
          # Minimum necessary to schedule the pod to a node
          requests:
            memory: "1Mi"
            cpu: "1m"
          # Max allowed
          limits:
            memory: "512Mi"
            cpu: "1000m"
        # Ports to open on a container
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        # Using robots.txt to verify liveness
        livenessProbe:
          httpGet:
            path: /robots.txt
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 120
          timeoutSeconds: 5
```

### base/service.yaml

The following addition to the "base/service.yaml" file enables port 80 on the
"foobar-static-files" pod to be accessed:

```
---
# foobar static files
apiVersion: v1
kind: Service
metadata:
  name: foobar-static-files
spec:
  selector:
    app: foobar-static-files
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    name: http
```

### base/networkpolicy.yaml

The following addition to the "base/networkpolicy.yaml" file enables port 80 on
the "foobar-static-files" pod to be reached from anywhere:

```
---
# Allow external HTTP traffic (ingress) to foobar-static-files pod
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: foobar-allow-external-http-to-static-files
spec:
  podSelector:
    matchLabels:
      app: foobar-static-files
  policyTypes:
  - Ingress
  ingress:
  - from: []
    ports:
      - port: 80
```

### base/ingress.yaml

The base/ingress.yaml file is changed to pass the following URL paths to the "foobar-static-files" pod, instead of to the "foobar-app" pod running the web application:

* /favicon.ico
* /robots.txt
* /sitemap.xml

All other URL paths go to the "foobar-app" pod.

----

WARNING

In the stock "k8s-new-app" example application, the "base/ingress.yaml" file
contains the following "rewrite" annotation in "Ingress" configurations:

```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  ...
  annotations:
    ...
    # Rewrite requests if training slash missing (/search -> /search/)
    nginx.ingress.kubernetes.io/rewrite-target: "/"
```

the "rewrite" annotation MUST be removed, as it forcibly rewrites all URL paths passed to the "foobar-static-files" pod to "/" (i.e. "/robots.txt" gets re-written to "/").

It is not clear if this rewrite rule is actually helpful in any way, so removing it should not cause a problem.

----

```
# Ingress configuration to expose Foobar public interface to internet
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: foobar-public-ingress

  labels:
    app.kubernetes.io/instance: foobar-public

  # See all available annotations:
  #  https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
  annotations:
    # Let's Encrypt certificate provisioning
    # Use "letsencrypt-staging" as the cluster-issuer if you will testing
    # multiple issues of certificates
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt"

spec:
  tls:
  - hosts:
    - <Foobar public domain_name>
    secretName: <Foobar public domain_name>-tls-secret
  rules:
  - host: <domain_name>
    http:
      paths:
      - path: /
        backend:
          serviceName: foobar-app
          servicePort: 8081
#----- The following lines are added -----
      - path: /favicon.ico
        pathType: Exact
        backend:
          serviceName: foobar-static-files
          servicePort: 80
      - path: /robots.txt
        pathType: Exact
        backend:
          serviceName: foobar-static-files
          servicePort: 80
      - path: /sitemap.xml
        pathType: Exact
        backend:
          serviceName: foobar-static-files
          servicePort: 80
#-----------------------------------------
```

## Overriding Files in overlays

If no changes are needed to the static files provided in the "base", then
nothing needs to be added to an overlay, as they will get the files in the
"base" by default.

Files are overridden by using a "configMapGenerator" in the "kustomization.yaml"
file in the overlay, which generates a ConfigMap, and a "patch" file to the
Deployment in the "base".

### Add the overridden versions of the files

The static files that are being overridden should be added to an
"overlays/\<ENV>/static-files" directory, where "\<ENV>" is the environment.
For example, override the "robots/robots.txt" and "sitemap/sitemap.xml" files
in the "prod" overlay, create the following file hierarchy:

```
k8s-foobar/
   |-- overlays/
         |-- prod/
               |-- static-files/
                     |-- robots/
                           |-- robots.txt
                     |-- sitemap/
                           |-- sitemap.xml
```


### overlays/\<ENV>/deployment-patch.yaml

A "deployment-patch.yaml" file adds the "volumes" and "volumeMounts" for the
overridden files:

```
- op: add
  path: /spec/template/spec/containers/0/volumeMounts/-
  value:
    name: static-files-volume-robots
    mountPath: "/usr/share/nginx/html/robots"
    readOnly: true
- op: add
  path: /spec/template/spec/volumes/-
  value:
    name: static-files-volume-robots
    configMap:
      # Provide the name of the ConfigMap you want to mount.
      name: foobar-static-files-robots-config
      # An array of keys from the ConfigMap to create as files
      items:
      - key: "robots.txt"
        path: "robots.txt"
- op: add
  path: /spec/template/spec/containers/0/volumeMounts/-
  value:
    name: foobar-files-volume-sitemap
    mountPath: "/usr/share/nginx/html/sitemap"
    readOnly: true
- op: add
  path: /spec/template/spec/volumes/-
  value:
    name: static-files-volume-sitemap
    configMap:
      # Provide the name of the ConfigMap you want to mount.
      name: foobar-static-files-sitemap-config
      # An array of keys from the ConfigMap to create as files
      items:
      - key: "sitemap.xml"
        path: "sitemap.xml"
```

### overlays/\<ENV>/kustomization.yaml

The following "configMapGenerator" in the "overlays/\<ENV>/kustomization.yaml"
file adds ConfigMaps for the two files being overriden, while the
"patchesJson6902" ensures that the "deployment-patch.yaml" file is used to
modify the "base/deployment.yaml" file:

```
configMapGenerator:
- name: foobar-static-files-robots-config
  files:
     - static-files/robots/robots.txt
- name: foobar-static-files-sitemap-config
  files:
     - static-files/sitemap/sitemap.xml

patchesJson6902:
  - path: deployment-patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: foobar-static-files
```
