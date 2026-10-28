param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [ValidateRange(20, 10000)][int]$Samples = 200,
    [int]$ExpectedApps = 0,
    [string]$OutputDirectory = "$PSScriptRoot/resultats"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')
$started = [DateTime]::UtcNow
$checks = [System.Collections.Generic.List[object]]::new()
$latencies = [System.Collections.Generic.List[double]]::new()
$servers = @{}
$sampleErrors = 0

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Details, [double]$DurationMs = 0)
    $checks.Add([pscustomobject]@{
        Test = $Name
        Statut = $Status
        DureeMs = [math]::Round($DurationMs, 2)
        Details = $Details
    })
    Write-Host ("[{0}] {1} - {2}" -f $Status, $Name, $Details)
}

function Get-HttpStatus {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 6
        return [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        return 0
    }
}

$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    $health = Invoke-RestMethod -Uri "$BaseUrl/sante" -TimeoutSec 6
    $healthStatus = if ($health.statut -eq 'ok' -and $health.base -eq 'accessible') { 'PASS' } else { 'FAIL' }
    Add-Check 'API /sante et connexion PostgreSQL' $healthStatus ($health | ConvertTo-Json -Compress) $watch.Elapsed.TotalMilliseconds
}
catch {
    Add-Check 'API /sante et connexion PostgreSQL' 'FAIL' $_.Exception.Message $watch.Elapsed.TotalMilliseconds
}

$watch.Restart()
try {
    $info = Invoke-RestMethod -Uri "$BaseUrl/info" -TimeoutSec 6
    if (-not $info.hote) { throw 'Le JSON /info ne contient pas le nom de l''hôte.' }
    Add-Check 'API /info' 'PASS' ("hote={0}; service={1}" -f $info.hote, $info.service) $watch.Elapsed.TotalMilliseconds
}
catch {
    $info = $null
    Add-Check 'API /info' 'FAIL' $_.Exception.Message $watch.Elapsed.TotalMilliseconds
}

$watch.Restart()
try {
    $row = Invoke-RestMethod -Uri "$BaseUrl/resultat?matricule=MAT000001" -TimeoutSec 6
    if ($row.matricule -ne 'MAT000001') { throw 'Le matricule retourné ne correspond pas à la demande.' }
    Add-Check 'Recherche résultat connu' 'PASS' ($row | ConvertTo-Json -Compress) $watch.Elapsed.TotalMilliseconds
}
catch {
    Add-Check 'Recherche résultat connu' 'FAIL' $_.Exception.Message $watch.Elapsed.TotalMilliseconds
}

foreach ($case in @(
    @{ Label = 'Matricule absent'; Url = "$BaseUrl/resultat"; Expected = 400 },
    @{ Label = 'Matricule inconnu'; Url = "$BaseUrl/resultat?matricule=BF000000"; Expected = 404 }
)) {
    $actual = Get-HttpStatus $case.Url
    $status = if ($actual -eq $case.Expected) { 'PASS' } else { 'FAIL' }
    Add-Check ("Erreur API : " + $case.Label) $status ("HTTP attendu={0}; HTTP observé={1}" -f $case.Expected, $actual)
}

Write-Host ("Mesure de répartition : {0} requêtes séquentielles vers {1}/info" -f $Samples, $BaseUrl)
$benchmark = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $Samples; $i++) {
    $requestWatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/info" -UseBasicParsing -TimeoutSec 6
        if ([int]$response.StatusCode -ne 200) { throw "HTTP $([int]$response.StatusCode)" }
        $reply = $response.Content | ConvertFrom-Json
        if (-not $reply.hote) { throw 'Réponse sans nom de machine.' }
        $hostName = [string]$reply.hote
        if (-not $servers.ContainsKey($hostName)) { $servers[$hostName] = 0 }
        $servers[$hostName]++
        $latencies.Add($requestWatch.Elapsed.TotalMilliseconds)
    }
    catch {
        $sampleErrors++
    }
}
$benchmark.Stop()
$successes = ($servers.Values | Measure-Object -Sum).Sum
if ($null -eq $successes) { $successes = 0 }
$rate = if ($benchmark.Elapsed.TotalSeconds -gt 0) { $successes / $benchmark.Elapsed.TotalSeconds } else { 0 }
$p95 = 0.0
if ($latencies.Count -gt 0) {
    $sorted = @($latencies | Sort-Object)
    $p95 = $sorted[[Math]::Min($sorted.Count - 1, [Math]::Ceiling($sorted.Count * 0.95) - 1)]
}
$spreadPct = 100.0
if ($successes -gt 0 -and $servers.Count -gt 0) {
    $spreadPct = 100.0 * (($servers.Values | Measure-Object -Maximum).Maximum - ($servers.Values | Measure-Object -Minimum).Minimum) / $successes
}
$configuredApps = $ExpectedApps
$envPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
if ($configuredApps -le 0 -and (Test-Path $envPath)) {
    $setting = Get-Content $envPath | Where-Object { $_ -match '^NB_APP=\d+$' } | Select-Object -First 1
    if ($setting) { $configuredApps = [int](($setting -split '=', 2)[1]) }
}
$minimumApps = if ($configuredApps -gt 0) { $configuredApps } else { 2 }
$benchmarkStatus = if ($sampleErrors -eq 0 -and $servers.Count -ge $minimumApps -and $spreadPct -lt 20) { 'PASS' } else { 'FAIL' }
$serverSummary = ($servers.GetEnumerator() | Sort-Object Key | ForEach-Object { "{0}:{1}" -f $_.Key, $_.Value }) -join '; '
Add-Check 'Répartition HTTP /info' $benchmarkStatus ("requêtes={0}; erreurs={1}; serveurs=[{2}]; debit_rps={3}; p95_ms={4}; ecart_pct={5}" -f $Samples, $sampleErrors, $serverSummary, [math]::Round($rate, 2), [math]::Round($p95, 2), [math]::Round($spreadPct, 2)) $benchmark.Elapsed.TotalMilliseconds

$prometheusUrl = 'http://127.0.0.1:9090'
$targets = $null
try {
    $prometheus = Invoke-RestMethod -Uri "$prometheusUrl/-/ready" -TimeoutSec 5
    $targets = Invoke-RestMethod -Uri "$prometheusUrl/api/v1/targets" -TimeoutSec 8
    $activeTargets = @($targets.data.activeTargets)
    $upTargets = @($activeTargets | Where-Object { $_.health -eq 'up' }).Count
    $downTargets = @($activeTargets | Where-Object { $_.health -ne 'up' } | ForEach-Object {
        "{0}/{1}: {2}" -f $_.labels.job, $_.labels.instance, $_.lastError
    })
    $targetStatus = if ($upTargets -eq $activeTargets.Count) { 'PASS' } else { 'WARN' }
    Add-Check 'Prometheus et cibles de supervision' $targetStatus ("ready={0}; cibles_up={1}/{2}; indisponibles={3}" -f $prometheus.Trim(), $upTargets, $activeTargets.Count, ($downTargets -join ' | '))
}
catch {
    Add-Check 'Prometheus et cibles de supervision' 'SKIP' $_.Exception.Message
}

try {
    $grafana = Invoke-RestMethod -Uri 'http://127.0.0.1:3000/api/health' -TimeoutSec 5
    Add-Check 'Grafana' 'PASS' ("database={0}; version={1}" -f $grafana.database, $grafana.version)
}
catch {
    Add-Check 'Grafana' 'SKIP' $_.Exception.Message
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$payload = [pscustomobject]@{
    date_utc = $started.ToString('o')
    base_url = $BaseUrl
    samples_demandes = $Samples
    requetes_reussies = $successes
    erreurs_reseau = $sampleErrors
    duree_benchmark_ms = [math]::Round($benchmark.Elapsed.TotalMilliseconds, 2)
    debit_reussites_par_seconde = [math]::Round($rate, 2)
    latence_p95_ms = [math]::Round($p95, 2)
    ecart_repartition_pct = [math]::Round($spreadPct, 2)
    serveurs = $servers
    verifications = @($checks)
    machines_vagrant = (vagrant status 2>&1 | Out-String).Trim()
    cibles_prometheus = if ($targets) { $targets.data.activeTargets } else { @() }
}
$jsonPath = Join-Path $OutputDirectory "validation-$stamp.json"
$csvPath = Join-Path $OutputDirectory "validation-$stamp.csv"
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
$checks | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host ("`nMesures enregistrées : {0} et {1}" -f $jsonPath, $csvPath)

$failed = @($checks | Where-Object { $_.Statut -eq 'FAIL' })
$warnings = @($checks | Where-Object { $_.Statut -in @('WARN', 'SKIP') })
if ($failed.Count -gt 0) {
    Write-Error ("{0} vérification(s) en échec ; consulter le rapport JSON/CSV." -f $failed.Count)
    exit 1
}
if ($warnings.Count -gt 0) {
    Write-Warning ("{0} contrôle(s) avec avertissement/ignoré(s) ; consulter le rapport JSON/CSV." -f $warnings.Count)
}
Write-Host 'VALIDATION FINALE : aucun contrôle exécuté n''a échoué.'
