# Contrôles rapides du répartiteur : R3, R4, R8 et E1. Lancer depuis la racine du dépôt.
param([string]$Vip = "192.168.63.10")

Write-Host "== R8 : ports redirigés vers l'hôte (uniquement sur les répartiteurs) =="
Select-String -Path Vagrantfile -Pattern "forwarded_port"

Write-Host "`n== Paramètres du .env (secrets non affichés) =="
if (Test-Path .env) { Select-String -Path .env -Pattern '^(NB_APP|ENABLE_HA|ENABLE_OBS)=' | ForEach-Object { $_.Line } }
else { Write-Host ".env absent" -ForegroundColor Red }

Write-Host "`n== lb1 : configuration HAProxy et services =="
vagrant ssh lb1 -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
vagrant ssh lb1 -c "sudo systemctl is-active haproxy"
vagrant ssh lb1 -c "sudo systemctl is-active keepalived"

Write-Host "`n== R3 / R4 : serveurs et sonde dans haproxy.cfg =="
vagrant ssh lb1 -c "grep -nE 'option httpchk|http-check|default-server|server ' /etc/haproxy/haproxy.cfg"
$nb = Select-String -Path .env -Pattern '^NB_APP=(\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
$n = vagrant ssh lb1 -c "grep -cE '^[[:space:]]*server[[:space:]]+app' /etc/haproxy/haproxy.cfg" |
     Where-Object { $_ -match '^\d+$' } | Select-Object -First 1
Write-Host "NB_APP = $nb ; serveurs app dans haproxy.cfg = $n"
if ($nb -and $n -and [int]$n -ne $nb) { Write-Host "ECART : relancer 'vagrant provision lb1 lb2'" -ForegroundColor Red }

Write-Host "`n== E1 : qui porte la VIP $Vip ? =="
vagrant ssh lb1 -c "ip -4 addr show | grep -F '$Vip/' || echo 'lb1 ne porte pas la VIP'"
vagrant ssh lb2 -c "ip -4 addr show | grep -F '$Vip/' || echo 'lb2 ne porte pas la VIP'"
