# UMD Web Static Files

Respository for creating a Docker image that holds default versions of commonly
used "static files" for web applications, such as:

* favicon.ico
* Google Site Verification HTML file
* robots.txt
* sitemap.xml

The Docker image uses a simple Nginx-based container, providing a generic
mechanism for accessing these files in a Kubernetes stack.

The "robots.txt" and "sitemap.xml" files are "default closed", i.e., the
"robots.txt" does not allow crawling, and the "sitemap.xml" is empty.

The files are provided in separate subdirectories so that a Kubernetes overlay
can override each file individually.

## Repository Files

### Dockerfile

The "Dockerfile" is used to build the Docker image.

```
> docker build -t docker.lib.umd.edu/umd-web-static-files:<VERSION> -f Dockerfile .
```

where \<VERSION> is the Docker image version to create.

The resulting Docker image should then be pushed to the Nexus.

### docker_config/nginx/

Contains the configuration for the Nginx server.

### static-files/

This directory contains a subdirectory for each file being served. The files
are organized in this manner, so that the files can be overridden indvidually
by a Kubernetes configuration.

The "google-file-upload" directory contains the HTML file for use with the
"HTML file upload" verification method provided by Google.
See [https://support.google.com/webmasters/answer/9008080](https://support.google.com/webmasters/answer/9008080).

## Kubernetes Configuration

The following is an example of using the "umd-web-static-files" image in
a Kubernetes configuration following the layout in
["k8s-new-app"](https://github.com/umd-lib/k8s-new-app).

In the following examples, the name of the application is "foobar". The files
will be served at the following URLs:

* https://foobar.lib.umd.edu/favicon.ico
* https://foobar.lib.umd.edu/googlee5878e862cad1cec.html
* https://foobar.lib.umd.edu/robots.txt
* https://foobar.lib.umd.edu/sitemap.xml

## Changes to the "base" overlay

The "base" overlay sets up the "foobar-static-files" pod running the
"umd-web-static-files" image.

### base/deployment.yaml

The following creates a "foobar-static-files" Deployment, with an associated
"foobar-static-files" pod.

The deployment uses the "umd-web-static-files" Nginx Docker image
(docker.lib.umd.edu/umd-web-static-files:latest), which serves a default set
of files from the "/usr/share/nginx/html" directory. Each file is in it's own
subdirectory, so it can be overridden by the overlays:

* favicon/favicon.ico
* google-file-upload/googlee5878e862cad1cec.html
* robots/robots.txt
* sitemap/sitemap.xml

The liveness probe use the "robots.txt" file for determining pod status.

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
      - image: docker.lib.umd.edu/umd-web-static-files:latest
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

The following addition to the "base/networkpolicy.yaml" allows enables port 80 on
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
* /googlee5878e862cad1cec.html
* /robots.txt
* /sitemap.xml

All other URL paths go to the "foobar-app" pod.

----

**WARNING**

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

the "rewrite" annotation MUST be removed, as it forcibly rewrites all URL paths
passed to the "foobar-static-files" pod to "/" (i.e. "/robots.txt" gets
re-written to "/").

It is not clear if this rewrite rule is actually helpful in any way, so
removing it should not cause a problem.

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
          service:
           name: foobar-static-files
           port:
             number: 80
      - path: /googlee5878e862cad1cec.html
        pathType: Exact
        backend:
          service:
            name: foobar-static-files
            port:
              number: 80
      - path: /robots.txt
        pathType: Exact
        backend:
          service:
            name: foobar-static-files
            port:
              number: 80
      - path: /sitemap.xml
        pathType: Exact
        backend:
          service:
            name: foobar-static-files
            port:
              number: 80
#-----------------------------------------
```

## Overriding Files in overlays

If no changes are needed to the static files provided in the "base", then
nothing needs to be added to an overlay, as it will get the files in the
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

## Variations for Special Cases

The above section describes a complete configuration for a web application. The
following are variations for the above for specific circumstances.

### Public/Staff interface in same application, but on different URLs

Example: ArchivesSpace (https://github.com/umd-lib/k8s-aspace)

In ArchivesSpace, there is a "public" interface at https://archives.lib.umd.edu/
and a "staff" interface at https://aspace.lib.umd.edu/. Both URLs are served
from the same web application.

In production, the "robots.txt" for the public interface should allow crawling,
while the "robots.txt" for the staff interface should not. Similarly, only the
"sitemap.xml" for the "public" interface should be populated.

This was implemented as follows:

1) In the "base" overlay, created a "base/static-files/extra/" directory, and
added "robots-public.txt" and "sitemap-public.xml" to it:

```
base/
  |-- static-files/
        |-- extra/
              |-- robots-public.txt
              |-- sitemap-public.xml
```

These file are the same as "robots.txt" and "sitemap.xml" files in
"umd-web-static-files", as they are "default closed". The actual production
versions will be in the "prod" overlay.

2) Modified "base/configmap.yaml", adding a "aspace-static-files-extra-config"
ConfigMap:

```
---
# Static files configmap
apiVersion: v1
kind: ConfigMap
metadata:
  name: aspace-static-files-extra-config
```

3) Modified "base/deployment.yaml" to include the additional static files:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aspace-static-files
  ...
  spec:
    ...
    template:
      ...
      spec:
        ...
        containers
        ...
          volumeMounts:
          - name: static-files-volume-extra
            mountPath: "/usr/share/nginx/html/extra"
            readOnly: true
        volumes:
          # You set volumes at the Pod level, then mount them into containers inside that Pod
          - name: static-files-volume-extra
            configMap:
              # Provide the name of the ConfigMap you want to mount.
              name: aspace-static-files-extra-config
              # An array of keys from the ConfigMap to create as files
              items:
              - key: "robots-public.txt"
                path: "robots-public.txt"
              - key: "sitemap-public.xml"
                path: "sitemap-public.xml"
```

4) Modified "base/kustomization.yaml" to add the additional static files to the "configMapGenerator" stanza:

```
# Configs to generate and link to the base resources
configMapGenerator:
- name: aspace-static-files-extra-config
  behavior: merge
  files:
    - static-files/extra/robots-public.txt
    - static-files/extra/sitemap-public.xml
```

5) In "base/ingress.yaml", added the followng rewrite rules to the ArchivesSpace public interface:

```
# Ingress configuration to expose ArchivesSpace public interface to internet
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: aspace-public-ingress
  ...
  annotations:
    ...
    # Rewrite rules to force public interface to use "public" versions
    # of robots.txt and sitemap.xml files
    #
    # Needed because "public" and "staff" interfaces are on different URLs
    # and require different robots.txt and sitemap.xml files
    nginx.ingress.kubernetes.io/configuration-snippet: |
        rewrite ^/sitemap.xml$ /extra/sitemap-public.xml break;
        rewrite ^/robots.txt$ /extra/robots-public.txt break;
```

6) In the "prod" overlay, add a "static-files/extra/" directory, with the "robots-public.txt" and "sitemap-public.xml" that are actually to be used on the production server:

```
prod/
  |-- static-files/
        |-- extra/
              |-- robots-public.txt
              |-- sitemap-public.xml
```

7) In the "prod/kustomization.yaml" file, add a "configMapGenerator" to merge the files into the "base" overlay (if a "configMapGenerator" stanza already exists, add all the lines except "configMapGenerator"):

```
configMapGenerator:
...
- name: aspace-static-files-extra-config
  behavior: merge
  files:
    - static-files/extra/robots-public.txt
    - static-files/extra/sitemap-public.xml
```
