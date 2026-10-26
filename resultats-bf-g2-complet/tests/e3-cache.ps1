# E3 - Gain du cache Redis : même charge avec le cache désactivé puis activé.
param([int]$Requetes = 2000, [int]$Concurrence = 50, [string]$Matricule = "BF000042", [int]$Ttl = 60)
. "$PSScriptRoot/lib.ps1"
$nb = Get-NbApp
function Regler([string]$v) {
    1..$nb | ForEach-Object { vagrant ssh "app$_" -c "sudo bash /vagrant/scripts/app-config.sh CACHE_TTL $v" | Out-Null }
    Start-Sleep -Seconds 5   # laisse HAProxy réintégrer les serveurs redémarrés
}
Write-Host "Cache désactivé (CACHE_TTL=0)..."
Regler "0"
$sans = Invoke-Charge -Requetes $Requetes -Concurrence $Concurrence -Matricule $Matricule
Write-Host "Cache activé (CACHE_TTL=$Ttl)..."
Regler "$Ttl"
Invoke-Charge -Requetes 50 -Concurrence 5 -Matricule $Matricule | Out-Null   # préchauffage
$avec = Invoke-Charge -Requetes $Requetes -Concurrence $Concurrence -Matricule $Matricule
Write-Host ("Sans cache : {0} req/s (échecs {1}) ; avec cache : {2} req/s (échecs {3})" -f $sans.rps, $sans.echecs, $avec.rps, $avec.echecs)
New-Item -ItemType Directory -Force -Path tests/resultats | Out-Null
$f = "tests/resultats/e3.csv"
if (-not (Test-Path $f)) { "date,nb_app,rps_sans_cache,rps_avec_cache" | Set-Content $f }
"{0},{1},{2},{3}" -f (Get-Date -Format "s"), $nb, $sans.rps, $avec.rps | Add-Content $f
