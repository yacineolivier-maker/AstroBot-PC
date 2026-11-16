# Profil d'un niveau avec la version de profilage de l'émulateur (symboles complets) : lance le niveau, avance,
# échantillonne les fils choisis (echantillonneur.exe), ferme proprement et restaure AstroBot.json.
# Résultats : Outils_Claude\work\profil-<étiquette>-<fil>.txt (à lire après la fin du script).
# Usage : profil.ps1 -Etiquette ag -Niveau underwater_aerial_garden [-Fils Thread_Gpu,CpSequencer] [-Secondes 30]
#         [-Variables @{...}] [-Emulateur Outils\KytyPS5_U59_prof_install]
param([Parameter(Mandatory)][string]$Etiquette, [string]$Niveau = 'underwater_aerial_garden',
      [string[]]$Fils = @('Thread_Gpu', 'CpSequencer', 'CP recorder'), [int]$Secondes = 30, [int]$Attente = 150,
      [hashtable]$Variables = @{}, [string]$Emulateur = 'Outils\KytyPS5_U59_prof_install')
$racine = if ($env:ASTROBOT_ROOT) { $env:ASTROBOT_ROOT } else { (Resolve-Path "$PSScriptRoot\..\..").Path }; $outils = "$racine\Developpement\outils"; $work = "$racine\Outils_Claude\work"
if (Get-Process kyty_emulator -ErrorAction SilentlyContinue) { throw 'kyty_emulator tourne déjà : profil annulé' }
$json = "$racine\Jeu\AstroBot.json"
$avant = [IO.File]::ReadAllText($json, [Text.Encoding]::UTF8)
try {
  $d = $avant | ConvertFrom-Json
  $v = @{}
  if ($d.variables) { $d.variables.PSObject.Properties | ForEach-Object { $v[$_.Name] = $_.Value } }
  foreach ($k in $Variables.Keys) { $v[$k] = $Variables[$k] }
  $d | Add-Member -NotePropertyName variables -NotePropertyValue ([pscustomobject]$v) -Force
  $d | Add-Member -NotePropertyName emulateur -NotePropertyValue $Emulateur -Force
  [IO.File]::WriteAllText($json, ($d | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  Start-Process "$racine\Jeu\AstroBot.exe" -ArgumentList '--niveau', $Niveau
  Start-Sleep -Seconds $Attente
  $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue
  if (-not $p) { throw 'le jeu ne tourne pas après le chargement' }
  & "$outils\pilote.ps1" -Script "maintenir W 3000; maintenir D 1500; maintenir W 3000; maintenir A 1500" *> $null
  foreach ($f in $Fils) {
    $o = "$work\profil-$Etiquette-$($f -replace '[^A-Za-z0-9]', '_').txt"
    & "$work\echantillonneur.exe" $p.Id $f $Secondes 1 $o
    "profil $f : $o (code $LASTEXITCODE)"
  }
  & "$outils\pilote.ps1" -Script 'titre' 2>$null
} finally {
  $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue
  if ($p) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(30000)) { Stop-Process -Id $p.Id -Force; 'arrêt forcé' } else { 'fermé proprement' } }
  Start-Sleep 5
  [IO.File]::WriteAllText($json, $avant, (New-Object Text.UTF8Encoding($false)))
}
