$ErrorActionPreference = "Stop"
$base = "http://127.0.0.1:8080"

Write-Host "Test de sante..."
$sante = Invoke-RestMethod "$base/sante"
$sante | Format-List

Write-Host "Test de recherche..."
$resultat = Invoke-RestMethod "$base/resultat?matricule=MAT000001"
$resultat | Format-List

if ($resultat.matricule -ne "MAT000001") {
    throw "Le matricule retourné est incorrect."
}

Write-Host "SUCCES : API et recherche fonctionnelles."