param(
    [Parameter(Mandatory)] [string]$VCenterServer,
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$Password,
    [Parameter(Mandatory)] [string]$YamlPath,
    [Parameter(Mandatory)] [string]$ServiceName,
    [Parameter(Mandatory)] [string]$ClusterName,
    [string]$ConfigYamlPath = ""
)

# ---------------------------------------------------------------------------
# Cmdlet discovery — run these interactively to verify exact names on your SDK
# version before executing the full script.
#
#   Get-Command -Module VMware.Sdk.vSphere.vCenter.NamespaceManagement |
#       Where-Object { $_.Name -match 'SupervisorService' } |
#       Select-Object Name | Sort-Object Name
#
# Tier 1 — service definition management (unchanged from pre-9.x):
#   Invoke-CreateNamespaceManagementSupervisorServices          POST /supervisor-services
#   Invoke-ListNamespaceManagementSupervisorServices            GET  /supervisor-services
#   Invoke-GetSupervisorServiceNamespaceManagement              GET  /supervisor-services/{svc}
#   Invoke-UpdateSupervisorServiceNamespaceManagement           PATCH
#   Invoke-DeleteSupervisorServiceNamespaceManagement           DELETE
#   Invoke-ActivateSupervisorServiceNamespaceManagement         PATCH ?action=activate
#   Invoke-DeactivateSupervisorServiceNamespaceManagement       PATCH ?action=deactivate
#   Invoke-CreateSupervisorServiceNamespaceManagementVersions   POST  /supervisor-services/{svc}/versions
#   Invoke-GetSupervisorServiceVersionNamespaceManagement       GET   /supervisor-services/{svc}/versions/{ver}
#
# Tier 2 — install/manage on a Supervisor (NEW in 9.x, replaces Cluster* cmdlets):
#   Invoke-CreateNamespaceManagementSupervisorSupervisorServices   POST /supervisors/{sup}/supervisor-services
#   Invoke-ListNamespaceManagementSupervisorSupervisorServices     GET  /supervisors/{sup}/supervisor-services
#   Invoke-GetSupervisorSupervisorServiceNamespaceManagement       GET  /supervisors/{sup}/supervisor-services/{svc}
#   Invoke-SetSupervisorSupervisorServiceNamespaceManagement       PUT  /supervisors/{sup}/supervisor-services/{svc}
#
# Supervisor listing (resolves supervisor ID from cluster):
#   Invoke-ListNamespaceManagementSupervisors                      GET  /supervisors
# ---------------------------------------------------------------------------

function Get-SupervisorId {
    <#
    .SYNOPSIS
    Resolves the Supervisor identifier required by the new API.
    The Supervisor ID is NOT the cluster MoRef — it is an opaque string
    returned by GET /api/vcenter/namespace-management/supervisors.
    #>
    param([string]$ClusterName)

    $cluster    = Get-Cluster -Name $ClusterName -ErrorAction Stop
    $clusterMoRef = $cluster.ExtensionData.MoRef.Value

    $supervisors = Invoke-ListNamespaceManagementSupervisors
    $supervisor  = $supervisors | Where-Object { $_.ConfiguredClusters -contains $clusterMoRef }

    if (-not $supervisor) {
        throw "No Supervisor found for cluster '$ClusterName' (MoRef: $clusterMoRef). " +
              "Verify the cluster has Workload Management enabled."
    }
    return $supervisor.Supervisor
}

function Invoke-WithRetry {
    # Retries a scriptblock when the error matches a pattern (e.g. package not yet reconciled).
    param(
        [scriptblock]$Action,
        [string]$RetryPattern = 'not found',
        [string]$Context      = '',
        [int]$RetryCount      = 6,
        [int]$RetryDelaySec   = 20
    )
    for ($i = 1; $i -le $RetryCount; $i++) {
        try {
            & $Action
            return
        } catch {
            if ($_.ToString() -match $RetryPattern -and $i -lt $RetryCount) {
                Write-Host "$Context Retrying in ${RetryDelaySec}s (attempt $i/$RetryCount)..."
                Start-Sleep -Seconds $RetryDelaySec
            } else {
                throw
            }
        }
    }
}

function Wait-ForVersionActivated {
    param([string]$ServiceName, [string]$Version, [int]$TimeoutSec = 120)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $v = $null
        try { $v = Invoke-GetSupervisorServiceVersionNamespaceManagement -SupervisorService $ServiceName -Version $Version } catch {}
        if ($v -and $v.State -eq "ACTIVATED") {
            Write-Host "[$ServiceName] Version $Version is ACTIVATED."
            return
        }
        Write-Host "[$ServiceName] Waiting for version $Version to activate (state: $($v.State))..."
        Start-Sleep -Seconds 10
    }
    throw "[$ServiceName] Timed out waiting for version $Version to reach ACTIVATED state."
}

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server $VCenterServer -User $Username -Password $Password | Out-Null

$yaml        = Get-Content -Path $YamlPath -Raw
$yamlB64     = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($yaml))
$versionMatches = [regex]::Matches($yaml, '(?m)^\s{2}version:\s*(.+)$')
$version     = $versionMatches[$versionMatches.Count - 1].Groups[1].Value.Trim()
$supervisorId = Get-SupervisorId -ClusterName $ClusterName

Write-Host "[$ServiceName] version=$version  supervisor=$supervisorId"

# --- Tier 1: Register or add version in global catalog (unchanged) ---
$existing = $null
try { $existing = Invoke-GetSupervisorServiceNamespaceManagement -SupervisorService $ServiceName } catch {}

if ($null -eq $existing) {
    Write-Host "[$ServiceName] Not found — registering..."
    $carvelVersionSpec = Initialize-NamespaceManagementSupervisorServicesVersionsCarvelCreateSpec -Content $yamlB64
    $carvelSpec        = Initialize-NamespaceManagementSupervisorServicesCarvelCreateSpec         -VersionSpec $carvelVersionSpec
    $createSpec        = Initialize-NamespaceManagementSupervisorServicesCreateSpec               -CarvelSpec  $carvelSpec
    Invoke-CreateNamespaceManagementSupervisorServices `
        -NamespaceManagementSupervisorServicesCreateSpec $createSpec | Out-Null
    Wait-ForVersionActivated -ServiceName $ServiceName -Version $version
} else {
    $existingVersion = $null
    try { $existingVersion = Invoke-GetSupervisorServiceVersionNamespaceManagement -SupervisorService $ServiceName -Version $version } catch {}

    if ($null -eq $existingVersion) {
        Write-Host "[$ServiceName] Already registered — adding new version $version..."
        $carvelVersionSpec = Initialize-NamespaceManagementSupervisorServicesVersionsCarvelCreateSpec -Content $yamlB64
        $versionSpec       = Initialize-NamespaceManagementSupervisorServicesVersionsCreateSpec       -CarvelSpec $carvelVersionSpec
        Invoke-CreateSupervisorServiceNamespaceManagementVersions `
            -SupervisorService $ServiceName `
            -NamespaceManagementSupervisorServicesVersionsCreateSpec $versionSpec | Out-Null
        Wait-ForVersionActivated -ServiceName $ServiceName -Version $version
    } else {
        Write-Host "[$ServiceName] Version $version already exists — skipping."
    }
}

# --- Tier 2: Install or update on the Supervisor (new API) ---
#
# Key spec differences vs. old ClusterSupervisorServices API:
#
#   OLD CreateSpec fields:                NEW CreateSpec fields:
#   SupervisorService (string)            SupervisorService (string)       ← same
#   Version (string)                      Version (string)                 ← same
#   YamlServiceConfig (base64 string)     YamlServiceConfig (base64 string)← same
#   n/a — added via Add-Member hack       IgnorePrecheckWarnings (bool)    ← proper SDK field (9.1+)
#
#   OLD SetSpec:                          NEW SetSpec:
#   -Version                              -Version                         ← same
#   n/a — Add-Member hack                 -IgnorePrecheckWarnings (bool)   ← proper SDK field (9.1+)
#
# The -Cluster parameter is replaced by -Supervisor (Supervisor ID string,
# NOT the ClusterComputeResource MoRef).

$onSupervisor = $null
try { $onSupervisor = Invoke-GetSupervisorSupervisorServiceNamespaceManagement -Supervisor $supervisorId -SupervisorService $ServiceName } catch {}

if ($null -eq $onSupervisor) {
    Write-Host "[$ServiceName] Installing on supervisor..."
    $installParams = @{
        SupervisorService      = $ServiceName
        Version                = $version
        IgnorePrecheckWarnings = $true
    }
    if ($ConfigYamlPath -ne "" -and (Test-Path $ConfigYamlPath)) {
        $installParams["YamlServiceConfig"] = [Convert]::ToBase64String(
            [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $ConfigYamlPath -Raw))
        )
    }
    $installSpec = Initialize-NamespaceManagementSupervisorsSupervisorServicesCreateSpec @installParams
    Invoke-WithRetry -Context "[$ServiceName] Carvel package not yet on supervisor." `
                     -RetryPattern 'package\.data\.packaging\.carvel\.dev.*not found' `
                     -Action {
        Invoke-CreateNamespaceManagementSupervisorSupervisorServices `
            -Supervisor $supervisorId `
            -NamespaceManagementSupervisorsSupervisorServicesCreateSpec $installSpec | Out-Null
    }
} else {
    Write-Host "[$ServiceName] Already on supervisor — updating to $version..."
    $setSpec = Initialize-NamespaceManagementSupervisorsSupervisorServicesSetSpec `
        -Version $version `
        -IgnorePrecheckWarnings $true
    Invoke-SetSupervisorSupervisorServiceNamespaceManagement `
        -Supervisor $supervisorId `
        -SupervisorService $ServiceName `
        -NamespaceManagementSupervisorsSupervisorServicesSetSpec $setSpec | Out-Null
}

Write-Host "[$ServiceName] Done."
Disconnect-VIServer -Confirm:$false | Out-Null
