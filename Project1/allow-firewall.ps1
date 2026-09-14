# Open the ports Erlang distribution needs, so remote workers can reach this
# machine. Run ONCE, as Administrator, on the SERVER laptop only.
#
#   Right-click PowerShell -> "Run as Administrator", then:
#     cd <repo>\Project1
#     powershell -ExecutionPolicy Bypass -File .\allow-firewall.ps1
#
#   If your Wi-Fi is on the Public profile (common for hotspots and campus
#   networks), add -SetPrivate to switch it to Private as well:
#     powershell -ExecutionPolicy Bypass -File .\allow-firewall.ps1 -SetPrivate
#
# 4369      is epmd, the Erlang port mapper daemon. A worker asks epmd on the
#           server which TCP port the "boss" node is listening on.
# 9100-9110 is the distribution port range this project pins in app.erl.
#           Erlang normally picks a random high port, which no fixed firewall
#           rule could ever cover -- hence the pinning.

#Requires -RunAsAdministrator

param(
    # Also switch the active network connection from Public to Private.
    # Windows blocks most inbound traffic on Public networks regardless of
    # firewall rules, so this is usually required on a hotspot.
    [switch]$SetPrivate,

    # Undo everything this script added.
    [switch]$Remove
)

$rules = @(
    @{ Name = "Erlang epmd (COP6539)";         Port = "4369" },
    @{ Name = "Erlang distribution (COP6539)"; Port = "9100-9110" }
)

if ($Remove) {
    foreach ($r in $rules) {
        $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-NetFirewallRule -DisplayName $r.Name
            Write-Host "Removed: $($r.Name)" -ForegroundColor Yellow
        } else {
            Write-Host "Not present: $($r.Name)" -ForegroundColor DarkGray
        }
    }
    Write-Host "`nDone. Firewall rules removed." -ForegroundColor Cyan
    exit 0
}

# ---------------------------------------------------------------- profile ---

$profiles = Get-NetConnectionProfile
Write-Host "Active network connections:" -ForegroundColor Cyan
$profiles | Select-Object Name, NetworkCategory, InterfaceAlias | Format-Table -AutoSize

$public = $profiles | Where-Object { $_.NetworkCategory -eq "Public" }

if ($public -and $SetPrivate) {
    foreach ($p in $public) {
        Set-NetConnectionProfile -InterfaceIndex $p.InterfaceIndex -NetworkCategory Private
        Write-Host "Switched '$($p.Name)' from Public to Private." -ForegroundColor Green
    }
    $public = $null
}

# ------------------------------------------------------------------ rules ---

foreach ($r in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Already present: $($r.Name)" -ForegroundColor DarkGray
        continue
    }
    New-NetFirewallRule -DisplayName $r.Name `
        -Direction Inbound -Action Allow -Protocol TCP `
        -LocalPort $r.Port -Profile Private, Domain | Out-Null
    Write-Host "Added: $($r.Name) -> TCP $($r.Port)" -ForegroundColor Green
}

# ----------------------------------------------------------------- report ---

Write-Host ""
if ($public) {
    Write-Host "WARNING --------------------------------------------------" -ForegroundColor Red
    Write-Host "These rules apply to the Private and Domain profiles, but" -ForegroundColor Red
    Write-Host "your active network is marked PUBLIC, so they will NOT take" -ForegroundColor Red
    Write-Host "effect and workers will not be able to connect." -ForegroundColor Red
    Write-Host ""
    Write-Host "Re-run this script with -SetPrivate to fix it:" -ForegroundColor Yellow
    Write-Host "  .\allow-firewall.ps1 -SetPrivate" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------" -ForegroundColor Red
    Write-Host ""
} else {
    Write-Host "Network profile is Private/Domain -- rules are in effect." -ForegroundColor Cyan
}

Write-Host "Give workers ONE of these addresses (the Wi-Fi one, normally):" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object InterfaceAlias, IPAddress |
    Format-Table -AutoSize

Write-Host "To undo these changes later:  .\allow-firewall.ps1 -Remove" -ForegroundColor DarkGray
