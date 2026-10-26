# R5 - Une écriture sur bdd1 est visible sur bdd2.
param([int]$Essais = 10)
$m = "REPL" + (Get-Date -Format "HHmmss")
Write-Host "Insertion de $m sur bdd1..."
vagrant ssh bdd1 -c "sudo bash /vagrant/scripts/test-replication.sh inserer $m" | Out-Host
$trouve = $false
for ($i = 1; $i -le $Essais; $i++) {
    $r = vagrant ssh bdd2 -c "sudo bash /vagrant/scripts/test-replication.sh lire $m" | Out-String
    if ($r -match $m) { $trouve = $true; Write-Host "Ligne visible sur bdd2 (essai $i) : $($r.Trim())"; break }
    Start-Sleep -Seconds 1
}
if (-not $trouve) { Write-Host "ECHEC : la ligne n'est pas visible sur bdd2." -ForegroundColor Red; exit 1 }
