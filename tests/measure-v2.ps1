# =============================================================================
# tests/measure-v2.ps1 - Scenario V2 : panne d'un serveur applicatif sous charge
#
# Envoie des requetes en continu (pause de 0,2 s) a /info via le repartiteur, declenche
# "vagrant halt app1" apres quelques secondes, puis affiche :
#   - le nombre de requetes envoyees et perdues
#   - la duree de la periode degradee
#   - le nombre d'erreurs survenues plus de 5 s apres la panne
#
# Usage (depuis le dossier du projet) :
#   powershell -ExecutionPolicy Bypass -File .\tests\measure-v2.ps1
#
# Option -Force : coupure brutale de la machine (vagrant halt --force), plus
# proche d'une vraie panne que l'arret propre par defaut.
#
# Apres la mesure, rallumer la machine : vagrant up app1
# =============================================================================
param(
    [string]$Url = "http://localhost:8080/info",
    [string]$Machine = "app1",
    [int]$DelaiPanne = 10,
    [int]$Duree = 60,
    [switch]$Force
)

$projet = (Get-Location).Path
$resultats = New-Object System.Collections.Generic.List[object]
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$panneLancee = $false
$tPanne = 0.0

Write-Host "Mesure V2 : requetes en continu (pause de 0,2 s) pendant $Duree s sur $Url"
Write-Host "La panne de $Machine sera declenchee a t = $DelaiPanne s."

while ($sw.Elapsed.TotalSeconds -lt $Duree) {
    if (-not $panneLancee -and $sw.Elapsed.TotalSeconds -ge $DelaiPanne) {
        $tPanne = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        # -Force : coupure brutale (comme un cable debranche), sans arret propre
        if ($Force) { $cmdArgs = @("halt", $Machine, "--force") } else { $cmdArgs = @("halt", $Machine) }
        Start-Process -FilePath "vagrant" -ArgumentList $cmdArgs `
            -WorkingDirectory $projet -WindowStyle Hidden
        $panneLancee = $true
        Write-Host "[t = $tPanne s] PANNE declenchee : vagrant $($cmdArgs -join ' ')"
    }

    $t = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $code = (& curl.exe -s -o NUL -m 3 -w "%{http_code}" $Url | Out-String).Trim()
    $resultats.Add([pscustomobject]@{ T = $t; Code = $code })
    Start-Sleep -Milliseconds 200
}

# ----------------------------- Resultats -------------------------------------
$total = $resultats.Count
$erreurs = @($resultats | Where-Object { $_.Code -ne "200" })
$nbErr = $erreurs.Count

Write-Host ""
Write-Host "================ RESULTATS V2 ================"
Write-Host "Panne declenchee a t =          $tPanne s"
Write-Host "Requetes envoyees :             $total (environ $([math]::Round($total / $Duree, 1)) requetes/s)"
Write-Host "Requetes reussies (200) :       $($total - $nbErr)"
Write-Host "Requetes perdues (erreurs) :    $nbErr"

if ($nbErr -gt 0) {
    $premiere = ($erreurs | Select-Object -First 1).T
    $derniere = ($erreurs | Select-Object -Last 1).T
    $degrade = [math]::Round($derniere - $premiere, 1)
    # La commande "vagrant halt" met plusieurs secondes avant que la machine ne
    # s'arrete vraiment : la panne EFFECTIVE commence a la premiere erreur.
    $tardives = @($erreurs | Where-Object { $_.T -gt ($premiere + 5) }).Count
    $delaiArret = [math]::Round($premiere - $tPanne, 1)
    $codes = ($erreurs | Group-Object Code | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ", "
    Write-Host "Delai commande -> 1re erreur :  $delaiArret s (arret reel de la machine)"
    Write-Host "Premiere erreur a t =           $premiere s"
    Write-Host "Derniere erreur a t =           $derniere s"
    Write-Host "Duree de la periode degradee :  $degrade s (entre 1re et derniere erreur)"
    Write-Host "Erreurs plus de 5 s apres la 1re erreur : $tardives"
    Write-Host "Codes d'erreur observes :       $codes"
} else {
    Write-Host "Aucune erreur observee."
}
Write-Host "=============================================="

$csv = Join-Path $env:TEMP "mesures-v2.csv"
$resultats | Export-Csv -Path $csv -NoTypeInformation
Write-Host "Mesures brutes enregistrees dans : $csv"
Write-Host "Pensez a rallumer la machine : vagrant up $Machine"
