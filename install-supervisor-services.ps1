param(
    [Parameter(Mandatory)] [string]$VCenterServer,
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$Password,
    [Parameter(Mandatory)] [string]$YamlPath,
    [Parameter(Mandatory)] [string]$ServiceName
)

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Connect-VIServer -Server $VCenterServer -User $Username -Password $Password | Out-Null

$yaml = Get-Content -Path $YamlPath -Raw

$existing = Get-VcNamespaceManagementSupervisorService `
    -SupervisorService $ServiceName -ErrorAction SilentlyContinue

if ($null -eq $existing) {
    Write-Host "[$ServiceName] Not found — registering..."
    $spec = Initialize-VcNamespaceManagementSupervisorServicesCreateSpec `
        -YamlServiceConfig (
            Initialize-VcNamespaceManagementSupervisorServicesYamlServiceConfig -Content $yaml
        )
    New-VcNamespaceManagementSupervisorService -RequestBody $spec | Out-Null
} else {
    Write-Host "[$ServiceName] Already registered — adding new version..."
    $versionSpec = Initialize-VcNamespaceManagementSupervisorServiceVersionsCreateSpec `
        -YamlServiceVersionConfig (
            Initialize-VcNamespaceManagementSupervisorServiceVersionsYamlServiceVersionConfig -Content $yaml
        )
    New-VcNamespaceManagementSupervisorServiceVersion `
        -SupervisorService $ServiceName -RequestBody $versionSpec | Out-Null
}

Write-Host "[$ServiceName] Done."
Disconnect-VIServer -Confirm:$false | Out-Null
