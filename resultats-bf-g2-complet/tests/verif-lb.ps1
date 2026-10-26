# Contrôles rapides du répartiteur : R3, R4, R8 et E1.
param([string]$Vip = "192.168.57.5")

Write-Host "== R8 : ports redirigés vers l'hôte (un seul attendu, sur lb1) =="
Select-String -Path Vagrantfile -Pattern "forwarded_port"

Write-Host "`n== lb1 : configuration HAProxy valide ? =="
vagrant ssh lb1 -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"

Write-Host "`n== R3 / R4 : serveurs engendrés et sonde =="
vagrant ssh lb1 -c "grep -E 'httpchk|http-check|default-server|server ' /etc/haproxy/haproxy.cfg"

Write-Host "`n== E1 : qui porte la VIP $Vip ? (lb1 attendu) =="
vagrant ssh lb1 -c "ip -4 addr show | grep -F '$Vip/' || echo 'lb1 ne porte pas la VIP'"
vagrant ssh lb2 -c "ip -4 addr show | grep -F '$Vip/' || echo 'lb2 ne porte pas la VIP (normal)'"
