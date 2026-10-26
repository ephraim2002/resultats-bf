# V1 - Répartition : 20 appels successifs à /info, comptage par serveur.
# Lancer depuis la racine du dépôt. Par défaut : la VIP du dépôt (192.168.63.10).
param(
    [string]$Url = "http://192.168.63.10/info",
    [int]$Appels = 20,
    [int]$Attendus = 0   # nombre de serveurs applicatifs ; 0 = lu dans .env (NB_APP)
)

if ($Attendus -eq 0 -and (Test-Path .env)) {
    $m = Select-String -Path .env -Pattern '^NB_APP=(\d+)'
    if ($m) { $Attendus = [int]$m.Matches[0].Groups[1].Value }
}

$reponses = 1..$Appels | ForEach-Object {
    try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 $Url).Content.Trim() }
    catch { "ERREUR" }
}
$groupes = $reponses | Group-Object | Sort-Object Name
$groupes | Format-Table Name, Count -AutoSize

$vus = @($groupes | Where-Object { $_.Name -ne "ERREUR" }).Count
if ($Attendus -gt 0 -and $vus -lt $Attendus) {
    Write-Host "ATTENTION : $vus serveur(s) distinct(s) vu(s) sur $Attendus attendu(s)." -ForegroundColor Red
}
$comptes = @($groupes | Where-Object { $_.Name -ne "ERREUR" } | ForEach-Object { $_.Count })
if ($Attendus -gt $vus) { $comptes += (1..($Attendus - $vus) | ForEach-Object { 0 }) }
if ($comptes.Count -gt 0) {
    $ecart = (($comptes | Measure-Object -Maximum).Maximum - ($comptes | Measure-Object -Minimum).Minimum) / $Appels * 100
    Write-Host ("Écart entre le plus et le moins sollicité : {0:N1} % (objectif < 20 %)" -f $ecart)
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force -Path tests/reseau/resultats | Out-Null
$reponses | Set-Content "tests/reseau/resultats/v1-$stamp.txt"
