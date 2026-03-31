# Getting Started with the Proactive Connect API

This guide covers the essential concepts, tooling, authentication, and query workflow required to integrate with the **Proactive Connect API**.

---

## 1. Introduction to GraphQL

GraphQL is a query language for APIs that gives consumers precise control over the data they receive. The following sections outline the key differences for developers familiar with REST:

### Single Endpoint, POST Requests

Unlike REST, where different HTTP verbs (GET, PUT, DELETE …) map to different operations, GraphQL uses a **single endpoint** that accepts **POST requests**. All operations — whether retrieving data or triggering a mutation — are sent to the same URL.

### JSON Request and Response Format

Requests and responses are both in the **JSON** format. A typical request body looks like this:

```json
{
  "query": "{ environment { availableToMe { nodes { id, name } } } }"
}
```

The server responds with a JSON object containing a `data` key (and optionally an `errors` key):

```json
{
  "data": {
    "environment": {
      "availableToMe": {
        "nodes": [
          { "id": "abc123", "name": "Production" }
        ]
      }
    }
  }
}
```

### Node IDs — Global Object Identifiers

Every object in the API is identified by a **globally unique, opaque Node ID** (a Base64-encoded string). These IDs are stable and can be used across different queries to reference the same object. For example:

```
RW52aXJvbm1lbnQ6NjM0ZDBlNzI5ODIzMTgyNWY4Y2VhNTNm
```

> **Tip:** Treat Node IDs as opaque strings — do not decode or construct them yourself.

### Consumer-Defined Field Selection

A key advantage of GraphQL is that **the consumer defines which fields to return**. This eliminates overfetching (receiving data that is not required) and underfetching (requiring multiple requests to assemble the desired data).

For example, to retrieve only an endpoint's OS and last contact time, the query specifies exactly those fields:

```graphql
{
  endpoint {
    byId(id: "RW5kcG9pbnQ6NTA3ZjE5MWU4MTBjMTk3MjlkZTg2MGVh") {
      general {
        os
        lastContact
      }
    }
  }
}
```

Only the requested fields are returned, minimizing payload size and unnecessary data transfer.

### `nodes` vs. `edges` in Paged Results

When querying collections (such as a list of endpoints or applications), the API returns results in a paginated structure that exposes two ways to access the items:

- **`nodes`** returns the items directly as a flat list. This is sufficient for most use cases.
- **`edges`** wraps each item in an object that additionally contains a `cursor` field, identifying the exact position of that item in the result set. This is useful if you need to resume pagination from a specific item rather than from the end of a page.

Unless you need per-item cursors, use `nodes`.

---

## 2. Tools

You can interact with the Proactive Connect API using any HTTP client, but dedicated GraphQL tools offer features like **schema exploration**, **auto-completion**, and **query validation** that make development significantly easier.

### Recommended Tools

| Tool | Type | Notes |
|------|------|-------|
| [Bruno](https://www.usebruno.com/) | Desktop client | Open-source, supports GraphQL natively, git-friendly collection format |
| [Postman](https://www.postman.com/) | Desktop / web client | Widely used, GraphQL support with schema introspection |
| [GraphiQL](https://github.com/graphql/graphiql) | Browser-based IDE | Interactive explorer with auto-complete and documentation sidebar |

### Loading the Schema into Your Tool

The **schema** is a machine-readable description of everything the API offers — all available queries, types, and fields. Loading it into your tool enables auto-completion and inline documentation while you write queries, and lets you explore what data is available without guessing.

Most GraphQL tools can load the API schema to enable auto-completion and validation. The Proactive Connect API exposes its schema definition at the `?sdl` path.

To retrieve the schema, send a **GET** request with your Bearer token, as in this example:

```
GET https://connect-euw.baramundi.cloud/eu/graphql?sdl
Authorization: Bearer {token}
```

In **Bruno**, you can configure the schema URL in the collection settings so that the editor provides auto-complete as you write queries.

---

## 3. API Endpoints

### Authentication Endpoint

The authentication endpoint is shared across all regions:

```
https://login.baramundi.cloud/login.baramundi.cloud/B2C_1A_SIGNIN/oauth2/v2.0/token
```

### GraphQL API Endpoints

The GraphQL API endpoint depends on the deployment region. Use the endpoint that corresponds to your environment.

| Region | GraphQL API |
|--------|-------------|
| EU | `https://connect-euw.baramundi.cloud/eu/graphql` |

---

## 4. Authentication

The Proactive Connect API uses [OAuth 2.0](https://www.microsoft.com/en-us/security/business/security-101/what-is-oauth) for authentication.

### Service-to-Service Communication

Currently, authentication for the Proactive Connect API is designed for **service-to-service (machine-to-machine) communication**. It uses the **OAuth 2.0 Client Credentials Grant** — there is no interactive user login involved. Your application authenticates directly with its own credentials.

### Configuring API Access

To use the API, you need a set of **client credentials** (Client ID and Client Secret). These are provisioned and managed through the Proactive Connect management portal. Contact your administrator to obtain or configure API access for your service account.

For detailed instructions on how to configure API access, refer to the [baramundi documentation](https://docs.baramundi.com/helpsetid=m_t_administration&externalid=a_proactive-hub_administration_api-proactive-connect).

> **Important:** Keep your Client Secret confidential. Never expose it in client-side code, public repositories, or logs.

### Requesting an Access Token

To authenticate, send a POST request to the **Azure AD B2C token endpoint** with your client credentials:

```
POST https://login.baramundi.cloud/login.baramundi.cloud/B2C_1A_SIGNIN/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={clientId}
&client_secret={clientSecret}
&scope=https://login.baramundi.cloud/app-connect-api/.default
```

The response contains an `access_token` that you include as a **Bearer token** in all subsequent API requests:

```json
{
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOi...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### Using the Token

Include the token in the `Authorization` header of every GraphQL request:

```
POST https://connect-euw.baramundi.cloud/eu/graphql
Content-Type: application/json
Authorization: Bearer {access_token}
```

> **Note:** Tokens expire after a limited time (see `expires_in` in the token response). Your application should handle token refresh by requesting a new token before the current one expires.

### Example: Authentication with PowerShell

> The following PowerShell snippets serve as **examples** to illustrate the authentication flow. You can use any HTTP client or programming language that supports OAuth 2.0.

#### Requesting a Token

```powershell

# Set your client credentials and Request a Bearer Token
$body = @{
    grant_type    = 'client_credentials'
    client_id     = '{clientId}'
    client_secret = '{clientSecret}'
    scope         = 'https://login.baramundi.cloud/app-connect-api/.default'
}

$tokenUrl = "https://login.baramundi.cloud/login.baramundi.cloud/B2C_1A_SIGNIN/oauth2/v2.0/token"
$response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
$token    = $response.access_token

# Prepare headers for GraphQL requests
$headers = @{ Authorization = "Bearer $token" }
```

> **Security note:** The example above uses plain-text variables for simplicity. In production, never hard-code credentials in scripts. See [Securing Credentials (Optional)](#securing-credentials-optional) below for a recommended approach.

#### Fetching the Schema

```powershell
$graphqlUrl = 'https://connect-euw.baramundi.cloud/eu/graphql'

$schema = Invoke-RestMethod -Uri "${graphqlUrl}?sdl" -Method Get -Headers @{ Authorization = "Bearer $token" }
Write-Host $schema
```

---

### Securing Credentials *(Optional)*

The authentication examples above pass credentials as plain-text variables. While this is sufficient to get started, it means secrets are visible in your script files and command history. For any non-throwaway usage, you should store credentials in a secure vault.

> **This step is technically not required** for the API to work — but without it, your client secret is exposed and the integration is insecure.

The following example uses the PowerShell **SecretManagement** and **SecretStore** modules:

#### One-Time Setup

The example script handles module installation and vault registration automatically on first run. If you prefer to set up manually, or are integrating into your own script, use the following:

```powershell
# Install secret management modules (only required once)
Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser

# Register a secret vault (only required once)
Register-SecretVault -Name ProactiveSecret -ModuleName Microsoft.PowerShell.SecretStore

# Store credentials
$credentials = @{
    ClientId     = '{clientId}'
    ClientSecret = '{clientSecret}'
}
Set-Secret -Name ProactiveSecret -Vault ProactiveSecret -Secret $credentials
```

#### Using Stored Credentials

Once your credentials are stored, replace the plain-text variables in the token request with:

```powershell
$creds = Get-Secret -Name ProactiveSecret -Vault ProactiveSecret -AsPlainText

$body = @{
    grant_type    = 'client_credentials'
    client_id     = $creds.ClientId
    client_secret = $creds.ClientSecret
    scope         = 'https://login.baramundi.cloud/app-connect-api/.default'
}
```

This way your Client ID and Client Secret are never stored in plain text within your script files.

---

## 5. Queries — User Flow

The Proactive Connect API organizes its queries under the following **top-level roots**:

| Root | Description |
|------|-------------|
| `company` | Access companies available to the authenticated service account |
| `environment` | Access environments and their metadata |
| `endpoint` | Access endpoint data (by ID, by environment, timeframe-based performance) |
| `search` | Search across entities |

Each root serves as the entry point into a specific domain of the API.

### Current Data vs. Timeframe-Based Data

The API distinguishes between two categories of data:

- **Current data** represents the latest known state of an object — for example, the operating system currently installed on an endpoint, or the list of applications present at the time of the last agent check-in. Current data is accessed directly through queries such as `endpoint.byId` or `environment.byId`.

- **Timeframe-based data** provides aggregated statistics and trend information over a reference period (e.g. the past 90, 60, or 30 days). This includes metrics such as crash and hang counts, network latency trends, and connectivity distributions. Timeframe-based data is accessed through the `timeframeBased` query, which requires a `timeframe` argument.

This distinction applies to both `endpoint` and `environment` queries. The `company` and `search` roots do not have timeframe-based variants.

The following overview illustrates the general query hierarchy (excerpt):

```graphql
{
  endpoint {
    byId(id: ID!)                            # Current data
    timeframeBased(timeframe: Timeframe!) {
      byId(id: ID!)                          # Timeframe-based data
    }
  }
  environment {
    byId(id: ID!)                             # Current data
    timeframeBased(timeframe: Timeframe!) {
      byId(id: ID!)                           # Timeframe-based data
    }
  }
  company {
    byId(id: ID!)                             # Current data only
  }
  search {
    endpoint(environmentId: ID!, filter: ...) # Filtered search
  }
}
```

The examples below illustrate the typical query workflow.

### Example 1: Get Companies Available To Me

Retrieve the companies accessible to your service account:

```graphql
{
  company {
    availableToMe(first: 5) {
      totalCount
      nodes {
        id
        name
        industry
        email
      }
    }
  }
}
```

##### Example response:

```json
{
  "data": {
    "company": {
      "availableToMe": {
        "totalCount": 2,
        "nodes": [
          { "id": "Q29tcGFueTo...", "name": "Acme Corp", "industry": "Aerospace", "email": "admin@acme.example" },
          { "id": "Q29tcGFueTo...", "name": "bartoso Ltd", "industry": "IT", "email": "admin@bartoso.example" }
        ]
      }
    }
  }
}
```

### Example 2: Get Environments Available To Me

Retrieve all environments your service account has access to, including company assignments and endpoint/user counts.

> **`managedCompanyName` vs. `assignedCompanyName`:** `managedCompanyName` identifies the company that owns and operates the environment. `assignedCompanyName` identifies the company the environment is assigned to for service delivery — typically a customer of the managing company. Both fields are identical when a company manages its own environment.

```graphql
{
  environment {
    availableToMe {
      totalCount
      nodes {
        id
        name
        managedCompanyName
        managedCompanyId
        assignedCompanyName
        assignedCompanyId
        endpointCount
        assignedUsersCount
      }
    }
  }
}
```

##### Example response:

```json
{
  "data": {
    "environment": {
      "availableToMe": {
        "totalCount": 1,
        "nodes": [
          {
            "id": "RW52aXJvbm1lbnQ6...",
            "name": "Production",
            "managedCompanyName": "baramundi GmbH",
            "managedCompanyId": "Q29tcGFueTo...",
            "assignedCompanyName": "Acme Corp",
            "assignedCompanyId": "Q29tcGFueT1...",
            "endpointCount": 142,
            "assignedUsersCount": 5
          }
        ]
      }
    }
  }
}
```

### Example 3: Get Endpoints by Environment (Paged)

Retrieve all endpoint IDs for a given environment. The API uses **cursor-based pagination** with a maximum of **10 results per page**.

- Send the initial request **without** an `after` parameter.
- Each response contains `pageInfo.endCursor` and `pageInfo.hasNextPage`.
- Pass `after: "{endCursor}"` in subsequent requests until `hasNextPage` is `false`.

**Initial request** (no cursor):

Specify the ID of one of your environments, as returned by the `{ environment { availableToMe } }` query.

```graphql
{
  endpoint {
    byEnvironmentId(environmentId: "RW52aXJvbm1lbnQ6NTA3ZjE5MWU4MTBjMTk3MjlkZTg2MGVh") {
      nodes {
        id
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
}
```

##### Example response:

```json
{
  "data": {
    "endpoint": {
      "byEnvironmentId": {
        "nodes": [
          { "id": "RW5kcG9pbnQ6..." },
          { "id": "RW5kcG9pbnQ6..." }
        ],
        "pageInfo": {
          "endCursor": "MTA=",
          "hasNextPage": true
        }
      }
    }
  }
}
```

**Subsequent requests** (pass the cursor from the previous response):

```graphql
{
  endpoint {
    byEnvironmentId(environmentId: "RW52aXJvbm1lbnQ6NTA3ZjE5MWU4MTBjMTk3MjlkZTg2MGVh", after: "MTA=") {
      nodes {
        id
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }
}
```

##### Example response:

```json
{
  "data": {
    "endpoint": {
      "byEnvironmentId": {
        "nodes": [
          { "id": "RW5kcG9pbnQ6..." },
          { "id": "RW5kcG9pbnQ6..." }
        ],
        "pageInfo": {
          "endCursor": "Y3Vyc29yOnYy...",
          "hasNextPage": true
        }
      }
    }
  }
}
```

> **How pagination works:** Each response includes a cursor that points to the next page. That cursor is passed in the `after` argument of the subsequent request to retrieve the next batch of results. The API supports `first`, `after`, `last`, and `before` arguments for navigating forward and backward through result sets.

### Example 4: Get Endpoint Detail by ID (Current Data)

Retrieve the current state of a specific endpoint using its Node ID. This queries **current data** — the latest known values as reported by the agent. The example below requests the `general` domain and the first page of installed `applications` to illustrate both a flat and a paged domain:

```graphql
{
  endpoint {
    byId(id: "RW5kcG9pbnQ6NTA3ZjE5MWU4MTBjMTk3MjlkZTg2MGVhOjUwN2YxZjc3YmNmODZjZDc5OTQzOTBiYw==") {
      id
      environmentId
      general {
        os
        fqdn
        lastContact
        lastLoggedInUser
      }
      applications {
        totalCount
        nodes {
          name
          publisher
          version
          installedOn
        }
        pageInfo {
          endCursor
          hasNextPage
        }
      }
    }
  }
}
```

##### Example response:

```json
{
  "data": {
    "endpoint": {
      "byId": {
        "id": "RW5kcG9pbnQ6...",
        "environmentId": "RW52aXJvbm1lbnQ6...",
        "general": {
          "os": "Windows 11 Pro",
          "fqdn": "workstation01.acme.example",
          "lastContact": "2026-03-02T08:45:00Z",
          "lastLoggedInUser": "jdoe"
        },
        "applications": {
          "totalCount": 87,
          "nodes": [
            { "name": "Microsoft Edge", "publisher": "Microsoft Corporation", "version": "132.0.0.0", "installedOn": "2025-11-10" },
            { "name": "Visual Studio Code", "publisher": "Microsoft Corporation", "version": "1.97.0", "installedOn": "2025-12-01" }
          ],
          "pageInfo": {
            "endCursor": "Y3Vyc29yOnYy...",
            "hasNextPage": true
          }
        }
      }
    }
  }
}
```

> **Note:** The example above covers a representative subset of available domains and fields. To explore the full set of domains and their fields, query the schema directly from the server — see [Loading the Schema into Your Tool](#loading-the-schema-into-your-tool). Paged domains support the `first`, `after`, `last`, and `before` arguments for navigation.

### Example 5: Get Endpoint Statistics (Timeframe-Based Data)

Retrieve aggregated stability and connectivity statistics for an endpoint over a defined reference period. Unlike the current data shown in Example 4, **timeframe-based data** includes trend values and delta comparisons against the previous reference period.

Available timeframes: `NINETY_DAYS` (and others as defined in the schema).

```graphql
{
  endpoint {
    timeframeBased(timeframe: NINETY_DAYS) {
      byId(id: "RW5kcG9pbnQ6NjM0ZDBlNzI5ODIzMTgyNWY4Y2VhNTNmOjRlYTc5OTdlY2ViMzY0NTdmZTlmZDM0OA==") {
        statistics {
          timeframe
          stability {
            currentCrashesCount
            currentHangsCount
            deltaCrashesCount
            deltaHangsCount
            lastApplicationCrash
            lastApplicationHang
            bluescreens {
              current
              delta
              last
            }
          }
          connectivity {
            capability {
              latency {
                totals {
                  combined
                  external
                  internal
                  trendCombined
                  trendExternal
                  trendInternal
                }
              }
              jitter {
                totals {
                  combined
                  external
                  internal
                  trendCombined
                  trendExternal
                  trendInternal
                }
              }
            }
            connectionType {
              percentageTotalMobile
              percentageTotalWired
              percentageTotalWireless
            }
            wifiSignalStrength {
              avgSignalStrength
              distributionByConnectivityGroup {
                bad
                good
                strong
                unusable
              }
            }
          }
        }
      }
    }
  }
}
```

##### Example response:

```json
{
  "data": {
    "endpoint": {
      "timeframeBased": {
        "byId": {
          "statistics": {
            "timeframe": "NINETY_DAYS",
            "stability": {
              "currentCrashesCount": 0,
              "currentHangsCount": 0,
              "deltaCrashesCount": 0,
              "deltaHangsCount": 0,
              "lastApplicationCrash": "2026-02-24T12:02:00.000Z",
              "lastApplicationHang": "2026-02-24T10:11:00.000Z",
              "bluescreens": {
                "current": 0,
                "delta": 0,
                "last": null
              }
            },
            "connectivity": {
              "capability": {
                "latency": {
                  "totals": {
                    "combined": 49.33,
                    "external": 86.21,
                    "internal": 12.97,
                    "trendCombined": 7.6,
                    "trendExternal": 15.63,
                    "trendInternal": -0.3
                  }
                },
                "jitter": {
                  "totals": {
                    "combined": 7.94,
                    "external": 14.39,
                    "internal": 1.98,
                    "trendCombined": 0.48,
                    "trendExternal": 1.13,
                    "trendInternal": -0.17
                  }
                }
              },
              "connectionType": {
                "percentageTotalMobile": 94,
                "percentageTotalWired": 1,
                "percentageTotalWireless": 5
              },
              "wifiSignalStrength": {
                "avgSignalStrength": 65,
                "distributionByConnectivityGroup": {
                  "bad": 27,
                  "good": 63,
                  "strong": 10,
                  "unusable": 0
                }
              }
            }
          }
        }
      }
    }
  }
}
```

---

## Next Steps

- **Explore the schema** — Load the SDL into a GraphQL tool and browse the available types and fields.
- **Query endpoint details** — Use `endpoint.byId` to retrieve current data for a specific endpoint (applications, hardware, connectivity, insights, and more).
- **Statistics and trends** — Use `endpoint.timeframeBased` to retrieve aggregated statistics and trend data over a selected reference period.
- **Pagination** — Review cursor-based pagination behaviour, particularly when working with large result sets such as endpoints or applications.
