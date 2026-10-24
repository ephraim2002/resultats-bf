# =============================================================================
# tests/test-idempotence.ps1 - Exigence R2 : idempotence du provisionnement
#
# 1. Releve l'empreinte (md5) des fichiers de configuration de chaque machine
# 2. Rejoue "vagrant provision" deux fois de suite (parametre -Rejeux)
# 3. Releve de nouveau les empreintes apres chaque rejeu et les compare
# 4. Verifie que le service et les donnees n'ont pas change
#
# A lancer sur une plateforme saine, JAMAIS apres la bascule de la base (V4).
#
# Usage (depuis le dossier du projet) :
#   powershell -ExecutionPolicy Bypass -File .\tests\test-idempotence.ps1
#
# Remarque : la sortie de "vagrant ssh" n'est jamais capturee dans une variable
# (cela peut bloquer sous Windows) ; les empreintes sont ecrites dans le dossier
# partage .vagrant\idem, depuis l'interieur des machines.
# =============================================================================
param(
    [string]$Machines = "bdd1,bdd2,app1,app2,lb1",
    [int]$Rejeux = 2,
    [string]$Url = "http://localhost:8080"
)

$liste = $Machines -split "," | ForEach-Object { $_.Trim() }
$dossierHote = Join-Path (Get-Location).Path ".vagrant\idem"
New-Item -ItemType Directory -Force -Path $dossierHote | Out-Null
Remove-Item "$dossierHote\*.txt" -ErrorAction SilentlyContinue

# Fichiers de configuration surveilles, par machine
$fichiers = @{
    "bdd1" = "/etc/postgresql/16/main/pg_hba.conf /etc/postgresql/16/main/postgresql.conf"
    "bdd2" = "/etc/postgresql/16/main/pg_hba.conf /etc/postgresql/16/main/postgresql.conf"
    "lb1"  = "/etc/haproxy/haproxy.cfg"
}
foreach ($n in 1..8) {
    $fichiers["app$n"] = "/etc/resultats-bf.env /etc/systemd/system/resultats-api.service"
}

function Empreintes([string]$phase) {
    foreach ($m in $liste) {
        $cible = "/vagrant/.vagrant/idem/$m-$phase.txt"
        vagrant ssh $m -c "mkdir -p /vagrant/.vagrant/idem; sudo md5sum $($fichiers[$m]) > $cible 2>&1"
    }
}

Write-Host "=== Empreintes AVANT les rejeux ==="
Empreintes "avant"

$durees = New-Object System.Collections.Generic.List[object]
$echecs = 0
for ($i = 1; $i -le $Rejeux; $i++) {
    Write-Host ""
    Write-Host "=== Rejeu $i / $Rejeux : vagrant provision ==="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    vagrant provision
    $code = $LASTEXITCODE
    $sw.Stop()
    if ($code -ne 0) {
        $echecs++
        Write-Host "ECHEC : vagrant provision a retourne le code $code"
    }
    $durees.Add([pscustomobject]@{ Rejeu = $i; Code = $code; Secondes = [math]::Round($sw.Elapsed.TotalSeconds, 0) })
    Empreintes "apres$i"
}

Write-Host ""
Write-Host "=== Comparaison des empreintes ==="
$differences = 0
foreach ($m in $liste) {
    $ref = Get-Content (Join-Path $dossierHote "$m-avant.txt")
    for ($i = 1; $i -le $Rejeux; $i++) {
        $apres = Get-Content (Join-Path $dossierHote "$m-apres$i.txt")
        $diff = Compare-Object $ref $apres
        if ($diff) {
            $differences++
            Write-Host "DIFFERENCE sur $m apres le rejeu $i :"
            $diff | Format-Table | Out-Host
        } else {
            Write-Host "OK : $m identique apres le rejeu $i"
        }
    }
}

Write-Host ""
Write-Host "=== Verifications du service ==="
Write-Host "/sante :"
curl.exe -s "$Url/sante"
Write-Host ""
Write-Host "Lignes dans la table resultats sur bdd1 (attendu : 50000) :"
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -tAc 'SELECT COUNT(*) FROM resultats;'"
Write-Host "bdd2 est toujours une replique (attendu : t) :"
vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();'"

Write-Host ""
Write-Host "================ RESULTATS R2 ================"
$durees | Format-Table -AutoSize | Out-Host
Write-Host "Rejeux en echec :              $echecs"
Write-Host "Differences de configuration : $differences"
if ($echecs -eq 0 -and $differences -eq 0) {
    Write-Host "CONCLUSION : provisionnement idempotent sur les fichiers surveilles."
} else {
    Write-Host "CONCLUSION : non idempotent, voir les messages ci-dessus."
}
Write-Host "=============================================="
