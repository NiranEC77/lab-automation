param(
    [Parameter(Mandatory)] [string]$VCenterServer,
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$Password,
    [Parameter(Mandatory)] [string]$YamlPath,
    [Parameter(Mandatory)] [string]$ServiceName,
    [Parameter(Mandatory)] [string]$ClusterId
)

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server $VCenterServer -User $Username -Password $Password | Out-Null

$yaml = Get-Content -Path $YamlPath -Raw

# Extract version from the Package spec (last "  version:" in the file)
$versionMatches = [regex]::Matches($yaml, '(?m)^\s{2}version:\s*(.+)$')
$version = $versionMatches[$versionMatches.Count - 1].Groups[1].Value.Trim()
Write-Host "[$ServiceName] Version: $version"

# --- Register / update global service catalog ---
$existing = $null
try {
    $existing = Invoke-GetSupervisorServiceNamespaceManagement -SupervisorService $ServiceName
} catch {}

if ($null -eq $existing) {
    Write-Host "[$ServiceName] Not found — registering..."
    $carvelSpec = Initialize-NamespaceManagementSupervisorServicesCarvelCreateSpec -Content $yaml
    $createSpec = Initialize-NamespaceManagementSupervisorServicesCreateSpec -CarvelCreateSpec $carvelSpec
    Invoke-CreateNamespaceManagementSupervisorServices -RequestBody $createSpec | Out-Null
} else {
    Write-Host "[$ServiceName] Already registered — adding new version..."
    $carvelVersionSpec = Initialize-NamespaceManagementSupervisorServicesVersionsCarvelCreateSpec -Content $yaml
    $versionSpec       = Initialize-NamespaceManagementSupervisorServicesVersionsCreateSpec -CarvelCreateSpec $carvelVersionSpec
    Invoke-CreateSupervisorServiceNamespaceManagementVersions `
        -SupervisorService $ServiceName -RequestBody $versionSpec | Out-Null
}

# --- Install / update on cluster ---
$clusterInstalled = $null
try {
    $clusterInstalled = Invoke-GetClusterSupervisorServiceNamespaceManagement `
        -Cluster $ClusterId -SupervisorService $ServiceName
} catch {}

if ($null -eq $clusterInstalled) {
    Write-Host "[$ServiceName] Installing on cluster $ClusterId..."
    $installSpec = Initialize-NamespaceManagementSupervisorServicesClusterSupervisorServicesCreateSpec `
        -SupervisorService $ServiceName `
        -Version          $version
    Invoke-CreateClusterSupervisorServiceNamespaceManagement `
        -Cluster $ClusterId `
        -NamespaceManagementSupervisorServicesClusterSupervisorServicesCreateSpec $installSpec | Out-Null
} else {
    Write-Host "[$ServiceName] Already installed on cluster — updating to $version..."
    $setSpec = Initialize-NamespaceManagementSupervisorServicesClusterSupervisorServicesSetSpec `
        -Version $version
    Invoke-SetClusterSupervisorServiceNamespaceManagement `
        -Cluster $ClusterId `
        -SupervisorService $ServiceName `
        -NamespaceManagementSupervisorServicesClusterSupervisorServicesSetSpec $setSpec | Out-Null
}

Write-Host "[$ServiceName] Done."
Disconnect-VIServer -Confirm:$false | Out-Null
