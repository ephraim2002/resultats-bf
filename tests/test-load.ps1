$ErrorActionPreference = "Stop"
$base = "http://127.0.0.1:8080"
$hosts = @()

1..20 | ForEach-Object {
    $r = Invoke-RestMethod "$base/info"
    $name = [string]$r.machine
    $hosts += $name
    Write-Host "$_ : $name"
}

Write-Host "`nRepartition observee :"
$hosts | Group-Object | Select-Object Name, Count | Format-Table -AutoSize

$distinct = @($hosts | Sort-Object -Unique)
if ($distinct.Count -lt 2) {
    Write-Warning "Une seule application observée. Vérifier /info, HAProxy et la santé des deux applications."
} else {
    Write-Host "SUCCES : plusieurs applications ont répondu."
}