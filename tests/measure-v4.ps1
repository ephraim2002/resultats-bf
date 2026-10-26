# =============================================================================
# tests/measure-v4.ps1 - Scenario V4 : panne de la base primaire + bascule
#
# ATTENTION : cette operation est DEFINITIVE. Apres la promotion, bdd2 devient
# la base primaire et ne redevient jamais une replique. Pour revenir a l'etat
# initial, il faut reconstruire la plateforme (vagrant destroy -f, puis up).
#
# Etapes chronometrees :
#   1. vagrant halt bdd1                       (la panne)
#   2. attente du 503 sur /sante               (le service echoue proprement)
#   3. promotion de bdd2 (scripts/failover-db.sh)
#   4. redirection des applications (scripts/switch-db-host.sh)
#   5. attente du retour a 200 sur /sante
#
# Usage (depuis le dossier du projet) :
#   powershell -ExecutionPolicy Bypass -File .\tests\measure-v4.ps1 -Apps "app1,app2,app3,app4"
# =============================================================================
param(
    [string]$Apps = "app1,app2",
    [string]$IpReplique = "192.168.63.32",
    [string]$Url = "http://localhost:8080"
)

$etapes = New-Object System.Collections.Generic.List[object]
$marque = [System.Diagnostics.Stopwatch]::StartNew()

function Code-Sante {
    (& curl.exe -s -o NUL -m 3 -w "%{http_code}" "$Url/sante" | Out-String).Trim()
}

function Fin-Etape([string]$nom) {
    $script:etapes.Add([pscustomobject]@{
        Etape    = $nom
        Secondes = [math]::Round($script:marque.Elapsed.TotalSeconds, 1)
    })
    $script:marque.Restart()
}

# ---------------------- Conditions de depart ---------------------------------
# Note : on n'enregistre JAMAIS la sortie de "vagrant ssh" dans une variable
# (|, Out-String) : sous Windows, cela peut bloquer la fenetre. On l'affiche.
Write-Host "Verification des conditions de depart..."
$codeAvant = Code-Sante
Write-Host "  /sante avant la panne : $codeAvant (attendu : 200)"
if ($codeAvant -ne "200") {
    Write-Host "Le service ne repond pas 200 : arret, rien n'a ete modifie."
    exit 1
}
Write-Host "  bdd2 doit etre une replique. Reponse de bdd2 (attendu : t) :"
vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();'"

Write-Host ""
Write-Host "ATTENTION : la promotion de bdd2 est DEFINITIVE."
Write-Host "Si la reponse de bdd2 ci-dessus n'est PAS la lettre t, ne continuez pas."
Write-Host "Applications qui seront redirigees : $Apps"
$reponse = Read-Host "Tapez OUI en majuscules pour continuer"
if ($reponse -ne "OUI") {
    Write-Host "Annule, rien n'a ete modifie."
    exit 1
}

$total = [System.Diagnostics.Stopwatch]::StartNew()
$marque.Restart()

# ---------------------- 1. La panne ------------------------------------------
Write-Host ""
Write-Host ">>> 1. PANNE : vagrant halt bdd1"
vagrant halt bdd1
Fin-Etape "1. Arret de bdd1 (vagrant halt)"

# ---------------------- 2. Le 503 propre -------------------------------------
Write-Host ""
Write-Host ">>> 2. Attente du 503 sur /sante"
$code = ""
while ($marque.Elapsed.TotalSeconds -lt 60) {
    $code = Code-Sante
    if ($code -eq "503") { break }
    Start-Sleep -Milliseconds 500
}
Fin-Etape "2. Detection : /sante repond $code"

Write-Host "Reponse complete de /sante pendant la panne (preuve pour le dossier) :"
curl.exe -s -i -m 3 "$Url/sante"
Write-Host ""
$marque.Restart()

# ---------------------- 3. La promotion --------------------------------------
Write-Host ""
Write-Host ">>> 3. PROMOTION de bdd2"
vagrant ssh bdd2 -c "echo PROMOUVOIR-BDD2 | sudo bash /vagrant/scripts/failover-db.sh"
$promotionOk = ($LASTEXITCODE -eq 0)
Fin-Etape "3. Promotion de bdd2 (failover-db.sh)"
if (-not $promotionOk) {
    Write-Host "ECHEC de la promotion : arret. Copiez le message ci-dessus."
    exit 1
}

# ---------------------- 4. Redirection des applications ----------------------
foreach ($a in ($Apps -split ",")) {
    $a = $a.Trim()
    Write-Host ""
    Write-Host ">>> 4. Redirection de $a vers $IpReplique"
    vagrant ssh $a -c "sudo bash /vagrant/scripts/switch-db-host.sh $IpReplique"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ATTENTION : echec de la redirection sur $a"
    }
}
Fin-Etape "4. Redirection des applications ($Apps)"

# ---------------------- 5. Retour a 200 --------------------------------------
Write-Host ""
Write-Host ">>> 5. Attente du retour a 200 sur /sante"
$code = ""
while ($marque.Elapsed.TotalSeconds -lt 60) {
    $code = Code-Sante
    if ($code -eq "200") { break }
    Start-Sleep -Milliseconds 500
}
Fin-Etape "5. Retour du service : /sante repond $code"
$tTotal = [math]::Round($total.Elapsed.TotalSeconds, 1)

# ---------------------- Verifications (hors chronometre) ---------------------
Write-Host ""
Write-Host ">>> Verifications apres la bascule"
Write-Host "Lecture d'un resultat via le repartiteur :"
curl.exe -s "$Url/resultat?matricule=MAT000001"
Write-Host ""
Write-Host "Ecriture sur bdd2 (preuve qu'elle est devenue primaire) :"
vagrant ssh bdd2 -c "sudo -u postgres psql -d resultats -c 'CREATE TABLE IF NOT EXISTS preuve_bascule (id int);'"

# ---------------------- Resume ------------------------------------------------
Write-Host ""
Write-Host "================ RESULTATS V4 ================"
$etapes | Format-Table -AutoSize | Out-Host
Write-Host "TEMPS TOTAL (de la panne au retour a 200) : $tTotal s"
Write-Host "=============================================="
Write-Host "Etat final : bdd1 eteinte, bdd2 primaire, applications sur bdd2."
Write-Host "Ne rejouez PAS vagrant provision sur bdd2 ni sur les applications."
