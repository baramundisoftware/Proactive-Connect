# =============================================================================
# PSC GraphQL API – Explorer Script
# =============================================================================
#
# User Flow:
#   1. Companies-AvailableToMe
#   2. Environments-AvailableToMe
#   3. Endpoint-ByEnvironmentId (paged, max 10 per request, cursor-based)
#   4. Endpoint-ById (full detail query)
#   5. Endpoint-TimeframeBased (performance statistics per timeframe)
#
# Required secrets (stored in SecretManagement vault "ProactiveSecret"):
#   - ClientId, ClientSecret
#
# Bearer Token generation (POST):
#   - Token URL, Client ID, Client Secret, Scope URL, Grant Type (client_credentials)
#
# GraphQL requests (POST, application/json):
#   - API URL, Bearer Token, Query in JSON format
#
# Paging (Example 3):
#   Works like a linked list – each response returns up to 10 endpoints and a
#   pageInfo.endCursor. Pass "after: <endCursor>" to fetch the next page until
#   hasNextPage is false.
#
# =============================================================================

# --- Helper: Execute a GraphQL query and return the result ---
function Invoke-GraphQL {
    param(
        [Parameter(Mandatory)] [string] $Query,
        [hashtable] $Headers,
        [string]    $Url
    )
    $body = @{ query = $Query } | ConvertTo-Json
    try {
        $result = Invoke-RestMethod -Uri $Url -Method Post `
            -Headers $Headers -ContentType 'application/json' -Body $body
        return $result
    } catch {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $reader.BaseStream.Position = 0
        Write-Host "HTTP Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        Write-Host ($reader.ReadToEnd()) -ForegroundColor Red
        return $null
    }
}

# --- Helper: Display result and wait for user ---
function Show-Result {
    param([Parameter(Mandatory)] $Data, [int] $Depth = 10)
    Write-Host ($Data | ConvertTo-Json -Depth $Depth)
    Read-Host "Press Enter to continue"; Clear-Host
}

# Import SecretManagement module so that Get-Secret / Set-Secret are available.
# Installs the module automatically if it is not yet present.
if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
    Write-Host "Installing Microsoft.PowerShell.SecretManagement..." -ForegroundColor Yellow
    Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser -Force -ErrorAction Stop
}
if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore)) {
    Write-Host "Installing Microsoft.PowerShell.SecretStore..." -ForegroundColor Yellow
    Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser -Force -ErrorAction Stop
}
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop

# Register the vault if it does not exist yet
if (-not (Get-SecretVault -Name ProactiveSecret -ErrorAction SilentlyContinue)) {
    Register-SecretVault -Name ProactiveSecret -ModuleName Microsoft.PowerShell.SecretStore
    Write-Host "Secret vault 'ProactiveSecret' registered." -ForegroundColor Green
}

# Retrieve client credentials from the local SecretManagement vault.
# If the secret does not exist yet, prompt the user and store it for future runs.
try {
    $creds = Get-Secret -Name ProactiveSecret -Vault ProactiveSecret -AsPlainText -ErrorAction Stop
} catch {
    Write-Host "Secret 'ProactiveSecret' not found. Please enter your credentials:" -ForegroundColor Yellow
    $clientId     = Read-Host "Client ID"
    $clientSecret = Read-Host "Client Secret"
    $creds = @{ ClientId = $clientId; ClientSecret = $clientSecret }
    Set-Secret -Name ProactiveSecret -Vault ProactiveSecret -Secret $creds
    Write-Host "Credentials saved to vault 'ProactiveSecret'." -ForegroundColor Green
}
$tokenUrl = 'https://login.baramundi.cloud/login.baramundi.cloud/B2C_1A_SIGNIN/oauth2/v2.0/token'

# Request a Bearer Token via OAuth2 Client Credentials Grant (POST)
Write-Host "`n--- Authentication: Requesting Bearer Token ---" -ForegroundColor Cyan
$body = @{
    grant_type    = 'client_credentials'
    client_id     = $creds.ClientId
    client_secret = $creds.ClientSecret
    scope         = 'https://login.baramundi.cloud/app-connect-api/.default'
}

$tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
$token = $tokenResponse.access_token
Write-Host "Bearer Token: $token"
Read-Host "Press Enter to continue"; Clear-Host

# Base URL for all GraphQL requests and reusable auth header
$graphqlUrl = 'https://connect-euw.baramundi.cloud/eu/graphql' # Data Center Europe
#$graphqlUrl = 'https://connect-use.baramundi.cloud/us/graphql' # Data Center US East
$headers    = @{ Authorization = "Bearer $token" }

# IDs used across Examples 3-5
# Replace these with IDs from your own environment (obtained from Examples 1 and 2)
$environmentId = "RW52aXJvbm1lbnQ6NjM0ZDBlNzI5ODIzMTgyNWY4Y2VhNTNm"
$endpointId    = "RW5kcG9pbnQ6NjM0ZDBlNzI5ODIzMTgyNWY4Y2VhNTNmOmRjMmI5YmMzNzZkZGVhZTUyMTM3YzQ5Yg=="

# Fetch the GraphQL schema definition (GET) to inspect available types & queries
Write-Host "`n--- Schema: GraphQL type and query definitions ---" -ForegroundColor Cyan
$schema = Invoke-RestMethod -Uri "${graphqlUrl}?sdl" -Method Get -Headers $headers
Show-Result $schema


# Example 1: Get companies available to the authenticated user (first 5)
Write-Host "`n--- Example 1: Companies available to this service account ---" -ForegroundColor Cyan
$companies = Invoke-GraphQL -Url $graphqlUrl -Headers $headers -Query @'
{
  company {
    availableToMe(first: 5) {
      totalCount
      nodes { id, name, industry, email }
    }
  }
}
'@
Show-Result $companies.data


# Example 2: Get environments available to the authenticated user
Write-Host "`n--- Example 2: Environments available to this service account ---" -ForegroundColor Cyan
$environments = Invoke-GraphQL -Url $graphqlUrl -Headers $headers -Query @'
{
  environment {
    availableToMe {
      totalCount
      nodes {
        id, name
        managedCompanyName, managedCompanyId
        assignedCompanyName, assignedCompanyId
        endpointCount, assignedUsersCount
      }
    }
  }
}
'@
Show-Result $environments.data


# Example 3: Collect ALL endpoint IDs for a given environment via cursor-based paging
Write-Host "`n--- Example 3: Collecting all endpoint IDs for environment $environmentId ---" -ForegroundColor Cyan
$allEndpointIds = @()
$hasNextPage    = $true
$cursor         = $null

do {
    $afterClause = if ($null -eq $cursor) { "" } else { ", after: `"$cursor`"" }

    $response = Invoke-GraphQL -Url $graphqlUrl -Headers $headers -Query @"
{
  endpoint {
    byEnvironmentId(environmentId: "$environmentId"$afterClause) {
      nodes { id }
      pageInfo { endCursor, hasNextPage }
    }
  }
}
"@

    if ($null -eq $response) { Write-Host "Request failed, aborting." -ForegroundColor Red; break }
    $pageData        = $response.data.endpoint.byEnvironmentId
    $allEndpointIds += $pageData.nodes
    $cursor          = $pageData.pageInfo.endCursor
    $hasNextPage     = $pageData.pageInfo.hasNextPage

    Write-Host "Page loaded – $($allEndpointIds.Count) endpoints collected so far..."
} while ($hasNextPage -eq $true -and $null -ne $cursor)

Write-Host "Done! $($allEndpointIds.Count) endpoint IDs found in total."
Show-Result $allEndpointIds


# Example 4: Fetch all available domains for a single endpoint.
# This is a comprehensive explorer query — in production, request only the fields you need.
# Available domains: applications, connectivity, general, hardware, insights, packages, performance, userFeedback
Write-Host "`n--- Example 4: Full endpoint detail for endpoint $endpointId ---" -ForegroundColor Cyan
$endpointDetail = Invoke-GraphQL -Url $graphqlUrl -Headers $headers -Query @"
{
  endpoint {
    byId(id: "$endpointId") {
      environmentId
      id
      applications {
        totalCount
        edges {
          cursor
          node {
            appId, architecture, context, endpointId, environmentId, id
            installationContextName, installationContextUserId
            installedOn, isCurrentlyInstalled, lastSeen
            name, publisher, sizeKB, type, version
          }
        }
        nodes {
          appId, architecture, context, endpointId, environmentId, id
          installationContextName, installationContextUserId
          installedOn, isCurrentlyInstalled, lastSeen
          name, publisher, sizeKB, type, version
        }
        pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
      }
      connectivity {
        adapters {
          ... on MobileAdapter   { lastActive, networkUsageLimit }
          ... on WiredAdapter    { lastActive }
          ... on WirelessAdapter { lastActive, networkUsageLimit, randomMacAddressEnabled }
        }
        connectionEvents(from: "2025-11-01", to: "2025-11-21") {
          edges {
            cursor
            node {
              connectionType, timestamp
              details { linkSpeed, name, receiveSpeedInKbps, transmitSpeedInKbps }
            }
          }
          nodes {
            connectionType, timestamp
            details { linkSpeed, name, receiveSpeedInKbps, transmitSpeedInKbps }
          }
          pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
          totalCount
        }
      }
      general {
        agentVersion, enrolledAgentVersion, fqdn
        lastContact, lastLoggedInUser, os, serialNumber
      }
      hardware {
        architecture, cpuDescription
        cpuLogicalCoresCount, cpuPhysicalCoresCount, cpuSocketsCount
        cpuSpeed, cpuType
        manufacturer, model, serialNumber, totalMemory
      }
      insights {
        anomalyLevel, anomalyScore, anomalyScoreTrend
        detectionRate, isIgnored, lastDetection, status
        factors { category, impactOnScore, metric }
      }
      packages {
        totalCount
        edges {
          cursor
          node {
            availableVersion, id
            installedVersion, packageId, packageName, publisher, targetState
          }
        }
        nodes {
          availableVersion, id
          installedVersion, packageId, packageName, publisher, targetState
        }
        pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
      }
      performance {
        battery {
          avgConsumptionMilliwatts, avgConsumptionPercentagePerHour
          fullTimeEstimate, healthPercentage, healthState
          batteries {
            cycleCount, designCapacity, fullChargeCapacity, healthPercentage
            id, manufacturer, name, serialNumber, uniqueId
          }
        }
        storage {
          instances {
            byteSize, hasConspicuousSmartAttributes
            healthStatus, healthStatusPercentage, name, type
            byDayMetrics {
              totalCount
              edges { cursor, node { day, healthStatus } }
              nodes { day, healthStatus }
              pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
            }
            smart {
              bufferSize, driveLetters, features, firmware, index, interface
              model, powerOnCount, powerOnHours, rotationRate
              serialNumber, standard, totalHostReads, totalHostWrites
              transferMode, type
              attributes { id, name, value }
            }
            volumes {
              byteSize, byteSizeRemaining, driveLetter
              isSystemVolume, label, status
            }
          }
        }
      }
      userFeedback {
        submissions {
          totalCount
          edges { cursor, node { comment, rating, timestamp, user } }
          nodes { comment, rating, timestamp, user }
          pageInfo { endCursor, hasNextPage, hasPreviousPage, startCursor }
        }
      }
    }
  }
}
"@
Show-Result $endpointDetail


# Example 5: Fetch aggregated stability and connectivity statistics for an endpoint (NINETY_DAYS)
# Timeframe-based data includes trend values and delta comparisons against the previous period
Write-Host "`n--- Example 5: Stability and connectivity statistics for endpoint $endpointId (last 90 days) ---" -ForegroundColor Cyan
$endpointStatsByTimeframe = Invoke-GraphQL -Url $graphqlUrl -Headers $headers -Query @"
{
  endpoint {
    timeframeBased(timeframe: NINETY_DAYS) {
      byId(id: "$endpointId") {
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
                  combined, external, internal
                  trendCombined, trendExternal, trendInternal
                }
              }
              jitter {
                totals {
                  combined, external, internal
                  trendCombined, trendExternal, trendInternal
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
                bad, good, strong, unusable
              }
            }
          }
        }
      }
    }
  }
}
"@
Show-Result $endpointStatsByTimeframe