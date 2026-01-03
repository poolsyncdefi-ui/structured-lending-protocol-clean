# fix_push.ps1 - Corriger le push
Write-Host ""
Write-Host "========================================"
Write-Host "  FIX GIT PUSH - BRANCH CONFIGURATION"
Write-Host "========================================"
Write-Host ""

# Vérifier la branche actuelle
$currentBranch = git branch --show-current
Write-Host "Branche actuelle: $currentBranch"
Write-Host "Commit: $(git rev-parse --short HEAD)"
Write-Host ""

# Vérifier les branches distantes
Write-Host "Branches distantes disponibles:"
git ls-remote --heads origin
Write-Host ""

if ($currentBranch -eq "main") {
    Write-Host "✅ Branche 'main' détectée"
    Write-Host "Pushing to origin/main..."
    git push -u origin main
} elseif ($currentBranch -eq "master") {
    Write-Host "✅ Branche 'master' détectée"
    Write-Host "Pushing to origin/master..."
    git push -u origin master
} else {
    Write-Host "⚠️  Branche inattendue: $currentBranch"
    $choice = Read-Host "Renommer en 'main'? (o/n)"
    if ($choice -eq 'o') {
        git branch -M main
        git push -u origin main
    }
}

Write-Host "`n✅ Opération terminée!"
Write-Host "GitHub: https://github.com/poolsyncdefi-ui/structured-lending-protocol-clean"
Read-Host "Appuyez sur Entrée pour continuer..."