# V6 (E1) - Panne du répartiteur actif : on interroge la VIP, jamais lb1 directement.
# Nécessite ENABLE_HA=true et lb1 + lb2 démarrés. Lancer depuis la racine du dépôt.
param([string]$Vip = "192.168.63.10", [int]$Duree = 60)
. "$PSScriptRoot/lib.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Invoke-Mesure -Url "http://$Vip/info" -Duree $Duree -DeclencheA 10 -Commande "vagrant halt lb1" `
              -Sortie "tests/reseau/resultats/v6-$stamp.csv"
Write-Host "`nPour rallumer : vagrant up lb1"
