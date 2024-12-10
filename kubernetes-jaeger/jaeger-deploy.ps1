<#---
title: Deploy Jaeger
---#>
# Set your variables
$TenantID = "<your-tenant-id>"
$ClientID = "<your-client-id>"
$ClientSecret = "<your-client-secret>"
$IngressHost = "jaeger.example.com"
$CookieSecret = "randomcookiebase64string" # Generate a secure random string (base64 encoded preferred)

# Encode the client secret to base64
$EncodedClientSecret = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ClientSecret))

# Now define all the manifests as here-strings using these variables
$NamespaceYAML = @"
apiVersion: v1
kind: Namespace
metadata:
  name: jaeger
"@

$SecretYAML = @"
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secret
  namespace: jaeger
type: Opaque
data:
  client-secret: $EncodedClientSecret
"@

$JaegerDeploymentYAML = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
        - name: jaeger
          image: jaegertracing/all-in-one:latest
          ports:
            - containerPort: 16686  # Jaeger UI port
            - containerPort: 14268  # Collector port
            - containerPort: 14250  # gRPC port
          env:
            - name: COLLECTOR_ZIPKIN_HTTP_PORT
              value: "9411"
"@

$JaegerServiceYAML = @"
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: jaeger
spec:
  ports:
    - port: 16686
      targetPort: 16686
      name: ui
    - port: 14268
      targetPort: 14268
      name: collector
    - port: 14250
      targetPort: 14250
      name: grpc
  selector:
    app: jaeger
"@

$OAuth2ProxyDeploymentYAML = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy
  namespace: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: oauth2-proxy
  template:
    metadata:
      labels:
        app: oauth2-proxy
    spec:
      containers:
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.4.0
          args:
            - "--provider=oidc"
            - "--oidc-issuer-url=https://login.microsoftonline.com/$TenantID/v2.0"
            - "--client-id=$ClientID"
            - "--client-secret-file=/secrets/client-secret"
            - "--email-domain=*"
            - "--cookie-secure=false"
            - "--cookie-secret=$CookieSecret"
            - "--upstream=http://jaeger.jaeger.svc.cluster.local:16686"
            - "--http-address=0.0.0.0:8080"
            - "--redirect-url=http://$IngressHost/"
          volumeMounts:
            - name: secret-volume
              mountPath: /secrets
              readOnly: true
      volumes:
        - name: secret-volume
          secret:
            secretName: oauth2-proxy-secret
            items:
              - key: client-secret
                path: client-secret
"@

$OAuth2ProxyServiceYAML = @"
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy
  namespace: jaeger
spec:
  ports:
    - port: 80
      targetPort: 8080
      name: http
  selector:
    app: oauth2-proxy
"@

$IngressYAML = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jaeger-ingress
  namespace: jaeger
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  rules:
    - host: $IngressHost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: oauth2-proxy
                port:
                  number: 80
"@

# Combine all YAML resources and pipe into kubectl apply
$AllYAML = $NamespaceYAML, $SecretYAML, $JaegerDeploymentYAML, $JaegerServiceYAML, $OAuth2ProxyDeploymentYAML, $OAuth2ProxyServiceYAML, $IngressYAML -join "`n---`n"

# Apply all manifests
$AllYAML | kubectl apply -f -
