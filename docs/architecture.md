# APIM Demo Architecture

## High-level flow

1. Client obtains OAuth2 access token from Microsoft Entra ID using client credentials flow.
2. Client calls APIM gateway with both:
   - `Authorization: Bearer <token>`
   - `Ocp-Apim-Subscription-Key: <product key>`
3. APIM applies policies:
   - `validate-jwt`
   - claim checks for admin route
   - rate limiting, CORS, headers, rewrite, error handling
4. APIM routes request to one of three backends:
   - Azure Function App (`function-api`)
   - Azure App Service Web API (`web-api` v1/v2)
   - VM-hosted Legacy API (`legacy-api`, on-prem simulation)

## ASCII diagram

```text
+--------------------+
| Demo Client        |
| (curl/Postman)     |
+---------+----------+
          |
          | OAuth2 client_credentials
          v
+--------------------+         +-----------------------------+
| Microsoft Entra ID |         | Azure API Management        |
| (token issuer)     +-------->+ (Developer SKU)             |
+--------------------+  Bearer | - Product subscription key  |
                                | - validate-jwt             |
                                | - claim authZ              |
                                | - throttling + transforms  |
                                +-----+-----------+----------+
                                      |           |
                     +----------------+           +----------------+
                     |                                     |
                     v                                     v
          +----------------------+                +----------------------+
          | Function App         |                | App Service Web API  |
          | /api/hello           |                | /hello /products     |
          | /api/orders          |                | /admin/health        |
          +----------------------+                +----------------------+

                                      |
                                      v
                            +----------------------+
                            | "On-Prem" VM (Ubuntu)|
                            | Legacy API on :5000  |
                            | /legacy/status       |
                            | /legacy/customers    |
                            +----------------------+
```

## On-prem simulation modes

### 1) Simple demo path (implemented by scripts)
- VM has a public IP.
- APIM reaches VM backend over public internet HTTP on port 5000.
- Label this clearly as demo-only and not production safe.

### 2) Enterprise-representative path (documented option)
- Place APIM in VNet mode (external or internal).
- Remove VM public ingress and expose legacy API privately.
- Connectivity options:
  - VNet peering between APIM VNet and onprem-vnet
  - Self-hosted APIM gateway near on-prem workloads
  - Private Link + VPN/ExpressRoute to private backend network

## Security model

- API audience: `api://<API_APP_ID>`
- Token validation at APIM using Entra OIDC metadata.
- App roles:
  - `Admin` for elevated route `/admin/health`
  - `Reader` for non-admin client
- APIM operation policy enforces 403 on missing `Admin` role.

## Observability

- APIM diagnostics configured to Application Insights.
- Correlation id injected via `x-correlation-id` header.
- Use Application Insights search to inspect:
  - Successful flows
  - 401 validation failures
  - 403 authorization failures
