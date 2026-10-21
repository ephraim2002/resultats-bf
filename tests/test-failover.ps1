$ErrorActionPreference = "Stop"
$base = "http://192.168.63.10"
$lb1Stopped = $false

try {
    Write-Host "Test avant panne..."
    Invoke-RestMethod "$base/sante" | Format-List

    Write-Host "Arrêt temporaire de lb1..."
    vagrant halt lb1
    if ($LASTEXITCODE -ne 0) { throw "Impossible d'arrêter lb1." }
    $lb1Stopped = $true

    Start-Sleep -Seconds 8
    Write-Host "Test de la VIP après panne..."
    Invoke-RestMethod "$base/sante" | Format-List

    Write-Host "SUCCES : la VIP répond après l'arrêt de lb1."
}
finally {
    if ($lb1Stopped) {
        Write-Host "Redémarrage de lb1..."
        vagrant up lb1
    }
}