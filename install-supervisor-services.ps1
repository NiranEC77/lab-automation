param(
    [Parameter(Mandatory)] [string]$VCenterServer,
    [Parameter(Mandatory)] [string]$Username,
    [Parameter(Mandatory)] [string]$Password,
    [Parameter(Mandatory)] [string]$YamlPath,
    [Parameter(Mandatory)] [string]$ServiceName
)

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

Connect-VIServer -Server $VCenterServer -User $Username -Password $Password | Out-Null

$Supervisor = Get-WMCluster | Select-Object -First 1
if (-not $Supervisor) { Write-Error "No supervisor cluster found."; exit 1 }

$yaml = Get-Content -Path $YamlPath -Raw
$existing = Get-WMSupervisorService -Name $ServiceName -ErrorAction SilentlyContinue

if ($null -eq $existing) {
    Write-Host "[$ServiceName] Not found — registering and activating..."
    $svc = New-WMSupervisorService -ContentYaml $yaml
    Enable-WMSupervisorService -WMCluster $Supervisor -WMSupervisorService $svc | Out-Null
} else {
    Write-Host "[$ServiceName] Already registered — adding new version..."
    New-WMSupervisorServiceVersion -WMSupervisorService $existing -ContentYaml $yaml | Out-Null
}

Write-Host "[$ServiceName] Done."
Disconnect-VIServer -Confirm:$false | Out-Null
