# V2 - Panne d'un serveur applicatif pendant une charge séquentielle (~10 req/s).
param([string]$Url = "http://192.168.57.5/info", [string]$Serveur = "app1", [int]$Duree = 60)
. "$PSScriptRoot/lib.ps1"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Invoke-Mesure -Url $Url -Duree $Duree -DeclencheA 10 -Commande "vagrant halt $Serveur" `
              -Sortie "tests/resultats/v2-$stamp.csv"
Write-Host "`nPour rallumer : vagrant up $Serveur"
