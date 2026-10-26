# V1 - Répartition : 20 appels successifs à /info, comptage par serveur.
param([string]$Url = "http://192.168.57.5/info", [int]$Appels = 20)
. "$PSScriptRoot/lib.ps1"

$reponses = 1..$Appels | ForEach-Object {
    try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 $Url).Content.Trim() } catch { "ERREUR" }
}
$groupes = $reponses | Group-Object | Sort-Object Name
$groupes | Format-Table Name, Count -AutoSize

$attendus = Get-NbApp
$vus = @($groupes | Where-Object { $_.Name -ne "ERREUR" }).Count
if ($attendus -gt 0 -and $vus -lt $attendus) {
    Write-Host "ATTENTION : $vus serveur(s) distinct(s) vu(s) sur $attendus attendu(s)." -ForegroundColor Red
}
$comptes = @($groupes | Where-Object { $_.Name -ne "ERREUR" } | ForEach-Object { $_.Count })
if ($attendus -gt $vus) { $comptes += (1..($attendus - $vus) | ForEach-Object { 0 }) }
if ($comptes.Count -gt 0) {
    $ecart = (($comptes | Measure-Object -Maximum).Maximum - ($comptes | Measure-Object -Minimum).Minimum) / $Appels * 100
    Write-Host ("Écart entre le plus et le moins sollicité : {0:N1} % (objectif < 20 %)" -f $ecart)
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force -Path tests/resultats | Out-Null
$reponses | Set-Content "tests/resultats/v1-$stamp.txt"
