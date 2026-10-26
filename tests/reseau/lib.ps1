# Fonctions communes aux scénarios V2 et V6 (PowerShell 5.1 ou 7).
# À lancer depuis la racine du dépôt (là où se trouve le Vagrantfile).

function Invoke-Mesure {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$Duree = 60,            # durée totale de l'observation (s)
        [int]$DeclencheA = 10,       # instant où la panne est provoquée (s)
        [string]$Commande,           # ex. "vagrant halt app1"
        [Parameter(Mandatory)][string]$Sortie  # fichier CSV brut
    )
    $debut = Get-Date
    $lignes = New-Object System.Collections.Generic.List[object]
    $job = $null
    while (((Get-Date) - $debut).TotalSeconds -lt $Duree) {
        $t = ((Get-Date) - $debut).TotalSeconds
        if (-not $job -and $Commande -and $t -ge $DeclencheA) {
            $dir = (Get-Location).Path
            $job = Start-Job -ScriptBlock { param($d, $c) Set-Location $d; Invoke-Expression $c } -ArgumentList $dir, $Commande
            Write-Host ("t={0:N1} s : {1}" -f $t, $Commande) -ForegroundColor Yellow
        }
        $ok = $false; $code = 0; $corps = ""
        try {
            $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 $Url
            $ok = $true; $code = [int]$r.StatusCode
            $corps = ($r.Content -replace "\s+", " ").Trim()
        } catch {
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        }
        $lignes.Add([pscustomobject]@{ t = [math]::Round($t, 2); ok = $ok; code = $code; corps = $corps })
        Start-Sleep -Milliseconds 100
    }
    if ($job) { Wait-Job $job -Timeout 120 | Out-Null; Receive-Job $job | Out-Null }

    New-Item -ItemType Directory -Force -Path (Split-Path $Sortie) | Out-Null
    $lignes | Export-Csv -NoTypeInformation -Encoding UTF8 $Sortie

    $erreurs = @($lignes | Where-Object { -not $_.ok })
    Write-Host ""
    Write-Host "Requêtes envoyées : $($lignes.Count)"
    Write-Host "Requêtes en erreur : $($erreurs.Count)"
    if ($erreurs.Count -gt 0) {
        $premiere = $erreurs[0].t; $derniere = $erreurs[-1].t
        Write-Host ("Première erreur : t={0} s ; dernière erreur : t={1} s" -f $premiere, $derniere)
        Write-Host ("Période dégradée : {0:N2} s" -f ($derniere - $premiere))
        if ($derniere -ge ($Duree - 1)) {
            Write-Host "ATTENTION : des erreurs persistent en fin de test, le service ne s'est pas rétabli." -ForegroundColor Red
        }
    } else {
        Write-Host "Aucune erreur observée."
    }
    Write-Host "Résultats bruts : $Sortie"
}
