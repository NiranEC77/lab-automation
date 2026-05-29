param(
    [Parameter(Mandatory)] [string]$VCenterServer,
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$Password,
    [Parameter(Mandatory)] [string]$ClusterName,
    [string]$SizeHint = "MEDIUM"
)

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

# ---------------------------------------------------------------------------
# Supervisor control plane size configuration
#
# 9.1+ path (ControlPlaneSettings API):
#   Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsGet     GET /supervisors/{sup}/control-plane-settings
#   Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsUpdate  PUT /supervisors/{sup}/control-plane-settings
#   Current size: response.Size.Identifier
#   Update spec:  Initialize-...-SizeUpdateSpec -Identifier <size>
#                 Initialize-...-UpdateSpec      -Size <sizeSpec>
#
# 9.0.x fallback path (Clusters API):
#   Invoke-GetClusterNamespaceManagement     GET /namespace-management/clusters/{cluster}
#   Invoke-UpdateClusterNamespaceManagement  PUT /namespace-management/clusters/{cluster}
#   Current size: response.SizeHint
#   Update spec:  Initialize-VcenterNamespaceManagementClustersUpdateSpec -SizeHint <size>
#
# Supervisor state polling:
#   Invoke-GetSupervisorNamespaceManagementSummary   GET /supervisors/{sup}/summary  (9.1+)
#   Invoke-GetClusterNamespaceManagement             GET /namespace-management/clusters/{cluster} (9.0.x)
#   ConfigStatus enum: CONFIGURING | RUNNING | ERROR | REMOVING
# ---------------------------------------------------------------------------

$sdkVersion = '13.5.0.25380678'
if (-not (Get-Module -ListAvailable -Name VMware.Sdk.vSphere | Where-Object { $_.Version.ToString() -eq $sdkVersion })) {
    Write-Host "Installing VMware.Sdk.vSphere $sdkVersion..."
    Install-Module -Name VMware.Sdk.vSphere -RequiredVersion $sdkVersion -Force -AllowClobber -Scope CurrentUser
    Write-Host "Module installed."
}
Import-Module VMware.Sdk.vSphere -RequiredVersion $sdkVersion -Force

function Wait-ForSupervisorRunning {
    param(
        [string]$SupervisorId,
        [string]$ClusterMoRef,
        [int]$TimeoutSec = 1200,
        [int]$PollIntervalSec = 15
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $status = $null
        try {
            if ($SupervisorId) {
                $summary = Invoke-GetSupervisorNamespaceManagementSummary -Supervisor $SupervisorId
                $status = $summary.ConfigStatus.ToString()
            } else {
                $info = Invoke-GetClusterNamespaceManagement -Cluster $ClusterMoRef
                $status = $info.ConfigStatus.ToString()
            }
        } catch {}
        Write-Host "Supervisor config status: $status"
        if ($status -eq 'RUNNING') {
            Write-Host "Supervisor is RUNNING."
            return
        }
        if ($status -eq 'ERROR') {
            throw "Supervisor entered ERROR state. Check vCenter for details."
        }
        Start-Sleep -Seconds $PollIntervalSec
    }
    throw "Timed out waiting for supervisor to reach RUNNING state."
}

function Get-SupervisorId {
    param([string]$ClusterName)
    $clusterMoRef = (Get-Cluster -Name $ClusterName -ErrorAction Stop).ExtensionData.MoRef.Value
    $summaries = Invoke-ListNamespaceManagementSupervisorsSummaries
    foreach ($item in $summaries.Items) {
        $topo = $null
        try { $topo = Invoke-GetSupervisorNamespaceManagementTopology -Supervisor $item.Supervisor } catch {}
        if ($topo | Where-Object { $_.Clusters -contains $clusterMoRef }) {
            return $item.Supervisor
        }
    }
    throw "No Supervisor found for cluster '$ClusterName' (MoRef: $clusterMoRef). Verify Workload Management is enabled."
}

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server $VCenterServer -User $Username -Password $Password | Out-Null

$clusterMoRef = (Get-Cluster -Name $ClusterName -ErrorAction Stop).ExtensionData.MoRef.Value
$supervisorId = Get-SupervisorId -ClusterName $ClusterName
Write-Host "Supervisor ID: $supervisorId"

# --- Try 9.1+ ControlPlaneSettings API first ---
$current = $null
try {
    $current = Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsGet -Supervisor $supervisorId
} catch {
    if ($_.ToString() -notmatch '404|NOT_FOUND|httpNotFound') { throw }
}

if ($current) {
    # 9.1+ path
    Write-Host "Current size (9.1+ API): $($current.Size.Identifier)"
    if ($current.Size.Identifier -eq $SizeHint) {
        Write-Host "Supervisor already set to $SizeHint — skipping."
        Disconnect-VIServer -Confirm:$false | Out-Null
        exit 0
    }
    Write-Host "Updating supervisor size to $SizeHint..."
    $sizeSpec   = Initialize-VcenterNamespaceManagementSupervisorsControlPlaneSettingsSizeUpdateSpec -Identifier $SizeHint
    $updateSpec = Initialize-VcenterNamespaceManagementSupervisorsControlPlaneSettingsUpdateSpec -Size $sizeSpec
    Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsUpdate `
        -Supervisor $supervisorId `
        -VcenterNamespaceManagementSupervisorsControlPlaneSettingsUpdateSpec $updateSpec | Out-Null
    Write-Host "Supervisor size updated to $SizeHint. Waiting for RUNNING state..."
    Wait-ForSupervisorRunning -SupervisorId $supervisorId
} else {
    # 9.0.x fallback path
    Write-Warning "ControlPlaneSettings API not available — using 9.0.x Clusters API."
    $clusterInfo = Invoke-GetClusterNamespaceManagement -Cluster $clusterMoRef
    Write-Host "Current size (9.0.x API): $($clusterInfo.SizeHint)"
    if ($clusterInfo.SizeHint -eq $SizeHint) {
        Write-Host "Supervisor already set to $SizeHint — skipping."
        Disconnect-VIServer -Confirm:$false | Out-Null
        exit 0
    }
    Write-Host "Updating supervisor size to $SizeHint..."
    $updateSpec = Initialize-VcenterNamespaceManagementClustersUpdateSpec -SizeHint $SizeHint
    Invoke-UpdateClusterNamespaceManagement `
        -Cluster $clusterMoRef `
        -VcenterNamespaceManagementClustersUpdateSpec $updateSpec | Out-Null
    Write-Host "Supervisor size updated to $SizeHint. Waiting for RUNNING state..."
    Wait-ForSupervisorRunning -ClusterMoRef $clusterMoRef
}

Disconnect-VIServer -Confirm:$false | Out-Null
