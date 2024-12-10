
# GitHub Action: Dynamic Deployment of a Secured Jaeger Instance to AKS

This repository contains a GitHub Action workflow that dynamically builds and deploys a Jaeger instance secured by OAuth2 Proxy to an Azure Kubernetes Service (AKS) cluster. The workflow generates Kubernetes manifests at runtime based on repository, branch, and environment variables, then applies them to your AKS cluster.

## What Does This Action Do?

1. **Namespace & Secrets**:  
   Creates a dedicated Kubernetes namespace and a secret containing OAuth2 credentials (e.g., Azure AD application client secret).

2. **Jaeger Deployment & Service**:  
   Deploys an "all-in-one" Jaeger instance which includes:
   - Jaeger UI (port 16686)
   - Collector endpoint (port 14268)
   - gRPC endpoint (port 14250)
   
   A Kubernetes Service is created to expose these ports internally.

3. **OAuth2 Proxy Deployment**:  
   Deploys an OAuth2 Proxy in front of the Jaeger UI to require authentication. Configuration is pulled dynamically from environment variables and secrets:
   - Uses Azure AD (OIDC) as the identity provider.
   - Validates users and restricts access to authorized personnel.
   - Uses a mounted Kubernetes Secret to store the client secret securely.

4. **Ingress Configuration**:  
   An Ingress resource is created to expose the Jaeger UI externally. The external DNS name (host) is generated dynamically from the repository and branch context. All inbound requests to the Jaeger UI route through the OAuth2 Proxy, ensuring users must log in before viewing traces.

## How the Action Works

### Trigger

The workflow triggers on `workflow_dispatch`, meaning you can manually start it from the GitHub Actions tab. This makes it suitable for controlled, on-demand deployments.

### Steps Involved

1. **Generate Kubernetes Manifest**:  
   The first step uses a PowerShell script within the GitHub Action to:
   - Construct a unique application name based on `github.repository` and `github.ref_name`.
   - Create a DNS name by appending the domain from repository variables.
   - Inject these values along with secret values (like `$tenant_id`, `$client_id`, and `$client_secret`) into a multi-document Kubernetes YAML manifest. 
   
   This manifest includes:
   - A `Namespace` resource.
   - A `Secret` for the OAuth2 Proxy client secret.
   - A `Deployment` and `Service` for Jaeger.
   - A `Deployment` for the OAuth2 Proxy.
   - An `Ingress` resource pointing to the Jaeger Service via OAuth2 Proxy.

   The manifest is written to `deployment.yml`.

2. **Login to Azure and Set AKS Context**:  
   The workflow logs into Azure using a GitHub secret (`AZURE_CREDENTIALS`) and sets the AKS context. This ensures `kubectl` commands operate on the correct cluster.

3. **Apply the Manifest**:  
   Once the Kubernetes context is set, the `deployment.yml` can be applied to the AKS cluster with:
   ```sh
   kubectl apply -f deployment.yml
   ```
   
   (*Note:* The actual `kubectl apply` command is commented out in the sample code, but you can uncomment it to apply changes.)

4. **Optional Rollout Restart**:  
   After applying the deployment, a `kubectl rollout restart` command can be used to refresh the Pods if needed. In the sample, this is also commented out but can be enabled as desired.

## Variables and Secrets

- **Variables (from `vars`):**  
  - `namespace`: The namespace in which to deploy (e.g., `jaeger`).
  - `DOMAIN`: The base domain for constructing the ingress hostname.
  - `ADMIN_APP_TENANTID`: The Azure AD tenant ID.
  - `ADMIN_APP_APPID` / `APP_ID`: The Azure AD application (client) ID.
  - `AZURE_RG`, `AZURE_AKS`: Azure resource group and AKS cluster name.
  
- **Secrets:**
  - `ADMIN_APP_SECRET`: The client secret for the Azure AD application.
  - `AZURE_CREDENTIALS`: Service principal credentials to log in to Azure.

These are used to dynamically configure the OAuth2 Proxy and the target environment.

## Before You Start

1. **Azure AD Application**:  
   Ensure you have an Azure AD Application registered. Copy its:
   - Client ID
   - Client Secret
   - Tenant ID

2. **GitHub Secrets & Variables**:  
   Store the Client Secret as a GitHub secret (`ADMIN_APP_SECRET`) and Tenant ID / Client ID as repository variables (`ADMIN_APP_TENANTID`, `ADMIN_APP_APPID`).  
   Store `AZURE_CREDENTIALS` as a GitHub secret containing the service principal JSON for accessing your AKS cluster.

3. **AKS Cluster**:  
   Make sure you have an AKS cluster ready and your GitHub Actions runner has permissions to manage it.

4. **DNS and TLS**:  
   The Ingress rule uses `$dnsname`, constructed from the repository and branch name plus `$DOMAIN`. Ensure DNS is properly configured. For production, consider adding TLS termination via ingress controllers or certificates.

## Verification

- Once deployed, navigate to the resulting ingress host:
  ```text
  https://<app_name>.<domain>
  ```
  You should be redirected to Azure AD for login. After successful authentication, the Jaeger UI should be accessible.

## Troubleshooting

- **Check Pod Logs**:
  ```sh
  kubectl logs deployment/<app_name> -n <namespace>
  kubectl logs deployment/oauth2-proxy -n <namespace>
  ```
  
- **Verify Secrets & Environment Variables**:  
  Ensure that the secrets and variables are correctly set in the GitHub repo. Missing or incorrect values can cause the OAuth2 Proxy to fail during startup or prevent login.

- **Networking & DNS**:
  Ensure your DNS is properly configured to point to your cluster’s ingress.

