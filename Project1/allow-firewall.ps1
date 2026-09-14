# Open the ports Erlang distribution needs, so remote workers can reach this
# machine. Run ONCE, as Administrator, on the SERVER laptop only.
#
#   Right-click PowerShell -> "Run as Administrator", then:
#     powershell -ExecutionPolicy Bypass -File .\allow-firewall.ps1
#
# 4369      is epmd, the Erlang port mapper daemon (how a worker looks up
#           which port the "boss" node is listening on).
# 9100-9110 is the distribution port range this project pins in app.erl.
#           Without pinning, Erlang picks a random high port and no fixed
#           firewall rule could cover it.

#Requires -RunAsAdministrator

$rules = @(
    @{ Name = "Erlang epmd (COP6539)";         Port = "4369" },
    @{ Name = "Erlang distribution (COP6539)"; Port = "9100-9110" }
)

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

Write-Host ""
Write-Host "Done. Note these rules apply to Private/Domain network profiles." -ForegroundColor Cyan
Write-Host "If your Wi-Fi is marked Public, either switch it to Private in" -ForegroundColor Cyan
Write-Host "Settings > Network, or use a phone hotspot (which is simpler and" -ForegroundColor Cyan
Write-Host "avoids campus Wi-Fi client isolation)." -ForegroundColor Cyan
Write-Host ""
Write-Host "This machine's IPv4 addresses:" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object InterfaceAlias, IPAddress |
    Format-Table -AutoSize
