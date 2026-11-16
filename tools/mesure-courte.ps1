# Mesure courte (15/11/2026, demande du porteur) : lance un niveau, repère l'arrivée dans le niveau d'après le relevé
# fps-*.csv (fin de l'écran de chargement, qui tient 30 i/s : premières 3 s consécutives sous 29 après 20 s ; sinon,
# niveau léger, départ fixé à $Repli s), puis déplace le personnage $Duree s avec pilote.ps1 (touches envoyées à la
# seule fenêtre du jeu, capture de la fenêtre du jeu seule) et mesure les i/s sur cette fenêtre. Ferme proprement et
# restaure AstroBot.json. Variables : comme mesure-sans-pilote.ps1 ; -Largeur/-Hauteur changent la résolution.
param([Parameter(Mandatory)][string]$Etiquette, [hashtable]$Variables = @{}, [string]$Emulateur = 'Outils\KytyPS5_MC_install',
      [string]$Niveau = 'underwater_aerial_garden', [int]$Duree = 120, [int]$Repli = 0, [int]$Max = 420,
      [int]$Largeur = 0, [int]$Hauteur = 0)
$r = if ($env:ASTROBOT_ROOT) { $env:ASTROBOT_ROOT } else { (Resolve-Path "$PSScriptRoot\..\..").Path }; $json = "$r\Jeu\AstroBot.json"; $j = "$r\Jeu\KytyPS5_U59\journaux"
$pilote = "$r\Developpement\outils\pilote.ps1"
$res = "$j\courte-$Etiquette-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
if (Get-Process kyty_emulator -ErrorAction SilentlyContinue) { throw 'kyty_emulator tourne déjà' }
$avant = [IO.File]::ReadAllText($json, [Text.Encoding]::UTF8)
function Lignes($csv) { if (-not $csv) { return @() }
  Get-Content $csv.FullName -ErrorAction SilentlyContinue | Select-Object -Skip 1 | ForEach-Object { $c = $_ -split ';'
    if ($c.Count -ge 4) { [pscustomobject]@{ s = [int]$c[1]; fps = [double]$c[3] } } } }
try {
  $d = $avant | ConvertFrom-Json; $v = @{}; $d.variables.PSObject.Properties | ForEach-Object { $v[$_.Name] = $_.Value }
  foreach ($e in $Variables.GetEnumerator()) { $v[$e.Key] = $e.Value }
  $d | Add-Member -NotePropertyName variables -NotePropertyValue ([pscustomobject]$v) -Force
  if ($Emulateur) { $d | Add-Member -NotePropertyName emulateur -NotePropertyValue $Emulateur -Force }
  if ($Largeur) { $d.largeurEcran = $Largeur; $d.hauteurEcran = $Hauteur }
  [IO.File]::WriteAllText($json, ($d | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  $t0 = Get-Date
  Start-Process "$r\Jeu\AstroBot.exe" -ArgumentList '--niveau', $Niveau
  Start-Sleep -Seconds 10
  [IO.File]::WriteAllText($json, $avant, (New-Object Text.UTF8Encoding($false)))
  # Arrivée dans le niveau
  $debut = $null; $csv = $null
  while (-not $debut -and ((Get-Date) - $t0).TotalSeconds -lt $Max -and (Get-Process kyty_emulator -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 2
    $csv = Get-ChildItem "$j\fps-2*.csv" | Where-Object { $_.LastWriteTime -ge $t0 } | Sort-Object LastWriteTime | Select-Object -Last 1
    $l = @(Lignes $csv | Where-Object { $_.s -gt 20 })
    for ($i = 0; $i -le $l.Count - 3; $i++) { if ($l[$i].fps -lt 29 -and $l[$i+1].fps -lt 29 -and $l[$i+2].fps -lt 29) { $debut = $l[$i].s; break } }
    if ($Repli -and -not $debut -and $l.Count -and $l[-1].s -ge $Repli) { $debut = $Repli; $leger = $true }
  }
  $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue
  if (-not $p) { "$Etiquette : ARRÊTÉ AVANT LA FIN" | Set-Content $res -Encoding UTF8; Get-Content $res; return }
  # Niveau lourd (16/11) : sans arrivée repérée, on ne mesure pas l'écran de chargement (30 i/s trompeurs). -Repli <s>
  # rétablit un départ fixe pour les niveaux légers qui tiennent 30.
  if (-not $debut) {
    "$Etiquette : NIVEAU NON ATTEINT en $Max s (chargement trop long ou bloqué) ; mesure annulée" | Set-Content $res -Encoding UTF8
    try { [void](& $pilote -Script "capture $Etiquette-chargement-$(Get-Date -Format HHmmss)") } catch {}
    [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(25000)) { Stop-Process -Id $p.Id -Force; 'fermeture forcée' | Add-Content $res } else { 'fermé proprement' | Add-Content $res }
    Get-Content $res; return }
  Start-Sleep -Seconds 5
  # Déplacement : avant, arrière, côtés, sauts ; capture de la fenêtre du jeu à mi-parcours
  # Trajet avant/arrière seul (porteur, 16/11) : la caméra reste tournée vers le décor chargé ; les pas de côté
  # la tournaient vers une vue plus légère et flattaient la mesure. Astro reste dans la même zone.
  # Le trajet W/S symétrique dérivait d'un lancement à l'autre (bout du chemin ou rambarde, ±5 i/s, 16/11 matin).
  # Butée : recul initial jusqu'à la rambarde du bord de l'île, puis chaque tour revient contre elle (S plus long que W).
  $tour = 'maintenir W 2000; maintenir S 2600; attendre 200'
  try { & $pilote -Script 'maintenir S 6000' | Out-Null } catch {}
  # Sans fenêtre au premier plan (session verrouillée, écran éteint), le pilote ne peut rien envoyer : Astro reste
  # immobile sur la vue de départ, plus lourde. Le résultat le dit (« IMMOBILE »), pour ne pas comparer à tort.
  $m0 = Get-Date; $n = 0; $echecs = 0; $capture = $null
  while (((Get-Date) - $m0).TotalSeconds -lt $Duree -and (Get-Process kyty_emulator -ErrorAction SilentlyContinue)) {
    try { & $pilote -Script $tour | Out-Null } catch { $echecs++; Start-Sleep -Seconds 2 }
    $n++
    if (-not $capture -and ((Get-Date) - $m0).TotalSeconds -ge $Duree / 2) {
      try { $capture = & $pilote -Script "capture $Etiquette-$(Get-Date -Format HHmmss)" } catch { $capture = "capture impossible : $_" } }
  }
  $fin = [int]((Get-Date) - $t0).TotalSeconds
  $csv = Get-ChildItem "$j\fps-2*.csv" | Where-Object { $_.LastWriteTime -ge $t0 } | Sort-Object LastWriteTime | Select-Object -Last 1
  $f = @(Lignes $csv | Where-Object { $_.s -ge $debut + 5 -and $_.s -lt $fin } | ForEach-Object fps)
  $moy = if ($f.Count) { ($f | Measure-Object -Average).Average } else { 0 }
  $tri = $f | Sort-Object; $p5 = if ($tri) { $tri[[int][Math]::Floor($tri.Count * 0.05)] } else { '-' }
  $quoi = if ($leger) { "départ fixé à $debut s (pas de baisse sous 29)" } else { "arrivée dans le niveau à $debut s" }
  $sous = if ($f.Count) { 100.0 * @($f | Where-Object { $_ -lt 29 }).Count / $f.Count } else { 0 }
  $p1 = if ($tri) { $tri[[int][Math]::Floor($tri.Count * 0.01)] } else { '-' }
  $mode = if ($echecs -eq 0) { 'en déplacement' } elseif ($echecs -ge $n) { 'IMMOBILE (pas de focus)' } else { "en déplacement partiel ($echecs tours sur $n sans focus)" }
  "$Etiquette : $quoi ; $($f.Count) s $mode : moyenne {0:N1}, médiane {1}, 5 % bas {2}, 1 % bas {3}, min {4}, secondes sous 29 : {5:N0} %" -f $moy, $(if ($tri) { $tri[[int]($tri.Count / 2)] } else { '-' }), $p5, $p1, $(if ($tri) { $tri[0] } else { '-' }), $sous | Set-Content $res -Encoding UTF8
  if ($capture) { "capture : $capture" | Add-Content $res }
  $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue
  if ($p) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(25000)) { Stop-Process -Id $p.Id -Force; 'fermeture forcée' | Add-Content $res } else { 'fermé proprement' | Add-Content $res } }
  else { 'ARRÊTÉ PENDANT LA MESURE' | Add-Content $res }
} finally { [IO.File]::WriteAllText($json, $avant, (New-Object Text.UTF8Encoding($false))) }
Get-Content $res
