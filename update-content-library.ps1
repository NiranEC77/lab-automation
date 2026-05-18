param(
    [Parameter(Mandatory)] [string]$VCenterServer,
    [Parameter(Mandatory)] [string]$LibraryName,
    [Parameter(Mandatory)] [string]$NewSubscriptionUrl,
    [string]$Username,
    [string]$Password
)

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

try {
    $connected = $global:DefaultVIServers | Where-Object { $_.Name -eq $VCenterServer -and $_.IsConnected }
    if (-not $connected) {
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        if ($Username -and $Password) {
            Connect-VIServer -Server $VCenterServer -User $Username -Password $Password | Out-Null
        } else {
            Connect-VIServer -Server $VCenterServer | Out-Null
        }
        Write-Host "Connected to $VCenterServer."
    }

    $library = Get-ContentLibrary -Name $LibraryName -ErrorAction SilentlyContinue
    if (-not $library) {
        throw "Content Library '$LibraryName' not found on $VCenterServer."
    }
    if ($library.Type -eq 'Local') {
        throw "Content Library '$LibraryName' is a Local library — only Subscribed libraries have a subscription URL."
    }

    Write-Host "Updating subscription URL for '$LibraryName'..."
    Write-Host "  Old URL: $($library.SubscriptionUri)"
    Write-Host "  New URL: $NewSubscriptionUrl"

    Set-ContentLibrary -SubscribedContentLibrary $library -SubscriptionUri $NewSubscriptionUrl | Out-Null

    Write-Host "Forcing synchronization of '$LibraryName'..."
    Sync-ContentLibrary -SubscribedContentLibrary $library | Out-Null

    Write-Host "✅ '$LibraryName' subscription URL updated and sync triggered."
}
catch {
    Write-Error "Failed to update Content Library '$LibraryName': $_"
    exit 1
}
finally {
    Disconnect-VIServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}
