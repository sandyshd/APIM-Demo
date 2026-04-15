# Demo Talk Track

## 1. Set context (2 minutes)
- "This demo shows APIM fronting three backend types with layered security."
- "We enforce both subscription key and OAuth2 JWT at the gateway."
- "We also show lifecycle controls: revisions for safe changes and versions for breaking changes."

## 2. Show deployed resources (3 minutes)
- Open Resource Group.
- Show:
  - API Management instance (Developer SKU)
  - Function App
  - App Service Web API
  - Ubuntu VM (on-prem simulation)
  - Key Vault
  - Application Insights

## 3. Show APIM API inventory (3 minutes)
- In APIM > APIs:
  - `function-api`
  - `web-api` (v1 and v2 versions)
  - `legacy-api`
- In APIM > Products:
  - `DemoProduct` requiring subscription

## 4. Show security posture (5 minutes)
- In Entra ID > App registrations:
  - API app (`api://...` audience)
  - admin client app
  - user client app
- In APIM policy editor:
  - `validate-jwt`
  - role check on admin operation
- Mention expected behavior:
  - no token => 401
  - invalid token => 401
  - valid non-admin token on admin route => 403

## 5. Run test script live (5 minutes)
- Execute `./scripts/07-test-calls.ps1`
- Narrate each scenario and expected status.
- Point out response headers:
  - `x-correlation-id`
  - `x-powered-by`

## 6. Revision demo (5 minutes)
- Create revision 2 for `web-api`.
- Apply small non-breaking policy/header tweak.
- Call revision endpoint (using `;rev=2`) and show changed header.
- Promote revision to current.

## 7. Versioning demo (5 minutes)
- Call v1 endpoint: `/v1/web/products`.
- Call v2 endpoint: `/v2/web/products`.
- Show response schema difference (v2 includes `sku`, `unitPrice`, `category`).
- Explain this as a managed breaking change.

## 8. Hybrid integration close (2 minutes)
- Show `legacy-api` response proving APIM can front "on-prem" style backend.
- Explain production-ready path via private connectivity options.
