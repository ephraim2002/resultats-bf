# Fonctions communes des scripts de test. À lancer depuis la racine du dépôt.

function Get-NbApp {
    if (Test-Path config/noeuds.yml) { return @(Select-String -Path config/noeuds.yml -Pattern "role: app").Count }
    return 0
}

function Get-Code {
    param([string]$Url)
    try { return [int](Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 $Url).StatusCode }
    catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}

# Lit la sortie d'Apache Bench (ab).
function Get-ResultatAb {
    param([string]$Sortie)
    $rps = 0.0; $echecs = -1; $non2xx = 0
    if ($Sortie -match 'Requests per second:\s+([\d\.]+)') { $rps = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }
    if ($Sortie -match 'Failed requests:\s+(\d+)') { $echecs = [int]$Matches[1] }
    if ($Sortie -match 'Non-2xx responses:\s+(\d+)') { $non2xx = [int]$Matches[1] }
    return [pscustomobject]@{ rps = $rps; echecs = $echecs; non2xx = $non2xx }
}

function Invoke-Charge {
    param([int]$Requetes = 2000, [int]$Concurrence = 50, [string]$Matricule = "BF000042")
    $sortie = vagrant ssh lb1 -c "bash /vagrant/scripts/charge.sh $Requetes $Concurrence $Matricule" | Out-String
    return Get-ResultatAb $sortie
}

# Envoie ~10 requêtes/s vers $Url, déclenche $Commande à $DeclencheA secondes, écrit un CSV brut.
function Invoke-Mesure {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$Duree = 60,
        [int]$DeclencheA = 10,
        [string]$Commande,
        [Parameter(Mandatory)][string]$Sortie
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
    if ($job) { Wait-Job $job -Timeout 180 | Out-Null; Receive-Job $job | Out-Null }

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
