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
#   Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsGet     GET /supervisors/{sup}/control-plane-settings
#   Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsUpdate  PUT /supervisors/{sup}/control-plane-settings
#   Current size: response.Size.Identifier
#   Update spec:  Initialize-...-SizeUpdateSpec -Identifier <size>
#                 Initialize-...-UpdateSpec      -Size <sizeSpec>
# ---------------------------------------------------------------------------

$sdkVersion = '13.5.0.25380678'
if (-not (Get-Module -ListAvailable -Name VMware.Sdk.vSphere | Where-Object { $_.Version.ToString() -eq $sdkVersion })) {
    Write-Host "Installing VMware.Sdk.vSphere $sdkVersion..."
    Install-Module -Name VMware.Sdk.vSphere -RequiredVersion $sdkVersion -Force -AllowClobber -Scope CurrentUser
    Write-Host "Module installed."
}
Import-Module VMware.Sdk.vSphere -RequiredVersion $sdkVersion -Force

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

$supervisorId = Get-SupervisorId -ClusterName $ClusterName
Write-Host "Supervisor ID: $supervisorId"

$current = Invoke-VcenterNamespaceManagementSupervisorsControlPlaneSettingsGet -Supervisor $supervisorId
Write-Host "Current size: $($current.Size.Identifier)"

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

Write-Host "Supervisor size updated to $SizeHint."
Disconnect-VIServer -Confirm:$false | Out-Null
