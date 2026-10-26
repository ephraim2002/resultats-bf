# V3 - Montée en charge : ab -n 2000 -c 50 lancé depuis lb1. À exécuter une fois avec
# NB_APP=2 puis une fois avec NB_APP=4 (après vagrant up et vagrant provision lb1 lb2).
# Pour mesurer la base seule, désactiver le cache : tests/e3-cache.ps1 ou CACHE_TTL=0.
param([int]$Requetes = 2000, [int]$Concurrence = 50, [string]$Matricule = "BF000042")
. "$PSScriptRoot/lib.ps1"
$nb = Get-NbApp
Write-Host "NB_APP = $nb : ab -n $Requetes -c $Concurrence"
$r = Invoke-Charge -Requetes $Requetes -Concurrence $Concurrence -Matricule $Matricule
Write-Host ("Requêtes par seconde : {0}   Échecs : {1}   Non-2xx : {2}" -f $r.rps, $r.echecs, $r.non2xx)
New-Item -ItemType Directory -Force -Path tests/resultats | Out-Null
$f = "tests/resultats/v3.csv"
if (-not (Test-Path $f)) { "date,nb_app,requetes,concurrence,rps,echecs,non2xx" | Set-Content $f }
"{0},{1},{2},{3},{4},{5},{6}" -f (Get-Date -Format "s"), $nb, $Requetes, $Concurrence, $r.rps, $r.echecs, $r.non2xx | Add-Content $f
Write-Host "Ajouté à $f"
