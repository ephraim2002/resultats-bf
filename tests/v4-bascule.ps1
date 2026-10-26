# V4 / R6 - Panne de la base primaire et procédure de bascule chronométrée.
# DESTRUCTIF pour la base : bdd1 est arrêtée et bdd2 est promue.
# Après le test, reconstruire : vagrant destroy -f ; vagrant up
param([string]$Vip = "192.168.63.10", [string]$Replique = "192.168.63.32", [string]$Matricule = "BF000042")
. "$PSScriptRoot/lib.ps1"

$nb = Get-NbApp
if ($nb -lt 2) { Write-Host "config/noeuds.yml introuvable ou invalide : lancer vagrant up d'abord." -ForegroundColor Red; exit 1 }
if ((Get-Code "http://$Vip/sante") -ne 200) { Write-Host "État initial incorrect : /sante doit renvoyer 200." -ForegroundColor Red; exit 1 }

$journal = New-Object System.Collections.Generic.List[string]
$sw = [Diagnostics.Stopwatch]::StartNew()
function Log { param([string]$m) $l = ("{0,6:N1} s  {1}" -f $sw.Elapsed.TotalSeconds, $m); Write-Host $l; $journal.Add($l) }

Log "vagrant halt bdd1"
vagrant halt bdd1 | Out-Null
Log "bdd1 arrêtée"

# Observation de /sante : doit passer à 503 proprement (jamais de page blanche).
$codes = @{}
$premier503 = $null
while ($sw.Elapsed.TotalSeconds -lt 90) {
    $c = Get-Code "http://$Vip/sante"
    if ($codes.ContainsKey($c)) { $codes[$c]++ } else { $codes[$c] = 1 }
    if ($c -ne 200) { $premier503 = $c; Log "premier code différent de 200 sur /sante : $c"; break }
    Start-Sleep -Milliseconds 500
}

Log "promotion de bdd2"
vagrant ssh bdd2 -c "sudo bash /vagrant/scripts/bascule-bdd.sh" | ForEach-Object { Log "  bdd2 : $_" }

for ($i = 1; $i -le $nb; $i++) {
    vagrant ssh "app$i" -c "sudo bash /vagrant/scripts/app-config.sh DB_HOST $Replique" | ForEach-Object { Log "  $_" }
}
Log "serveurs applicatifs reconfigurés"

$retabli = $false
while ($sw.Elapsed.TotalSeconds -lt 180) {
    if ((Get-Code "http://$Vip/sante") -eq 200) { $retabli = $true; break }
    Start-Sleep -Milliseconds 500
}
$total = $sw.Elapsed.TotalSeconds
if ($retabli) { Log "/sante renvoie 200 : service rétabli" } else { Log "service NON rétabli après 180 s" }
$res = Get-Code "http://$Vip/resultat?matricule=$Matricule"
Log "GET /resultat?matricule=$Matricule : code $res"
Log ("Durée totale de la bascule (de l'arrêt au service rétabli) : {0:N1} s" -f $total)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Force -Path tests/resultats | Out-Null
$journal | Set-Content "tests/resultats/v4-$stamp.txt"
Write-Host "`nJournal : tests/resultats/v4-$stamp.txt"
Write-Host "Pour revenir à l'état initial : vagrant destroy -f ; vagrant up" -ForegroundColor Yellow
