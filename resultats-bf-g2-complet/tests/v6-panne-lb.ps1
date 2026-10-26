# V6 (E1) - Panne du répartiteur actif : on interroge la VIP, pas lb1.
param([string]$Vip = "192.168.57.5", [int]$Duree = 60)
. "$PSScriptRoot/lib.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Invoke-Mesure -Url "http://$Vip/info" -Duree $Duree -DeclencheA 10 -Commande "vagrant halt lb1" `
              -Sortie "tests/resultats/v6-$stamp.csv"
Write-Host "`nPour rallumer : vagrant up lb1 (lb1 reprend la VIP, préemption activée)"
