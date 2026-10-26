# V5 / R1 - Reconstruction intégrale : vagrant destroy -f puis vagrant up, chronométrés.
# DESTRUCTIF : supprime toutes les VM du projet.
param([string]$Vip = "192.168.63.10")
. "$PSScriptRoot/lib.ps1"
if ((Read-Host "Cela détruit toutes les VM du projet. Taper OUI pour continuer") -ne "OUI") { exit 0 }

$sw = [Diagnostics.Stopwatch]::StartNew()
vagrant destroy -f
$tDestroy = $sw.Elapsed.TotalSeconds
vagrant up
$tUp = $sw.Elapsed.TotalSeconds - $tDestroy

$code = Get-Code "http://$Vip/sante"
$res = Get-Code "http://$Vip/resultat?matricule=BF000042"
$lignes = @(
    ("destroy : {0:N0} s" -f $tDestroy),
    ("up : {0:N0} s" -f $tUp),
    ("total : {0:N0} s ({1:N1} min)" -f $sw.Elapsed.TotalSeconds, $sw.Elapsed.TotalMinutes),
    "/sante : $code ; /resultat : $res"
)
$lignes | ForEach-Object { Write-Host $_ }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force -Path tests/resultats | Out-Null
$lignes | Set-Content "tests/resultats/v5-$stamp.txt"
if ($code -ne 200) { Write-Host "Plateforme non fonctionnelle après la reconstruction." -ForegroundColor Red }
