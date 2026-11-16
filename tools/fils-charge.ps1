# Charge par fil de kyty_emulator (15/11/2026) : lance un niveau (mesure-courte.ps1 en arrière-plan n'est pas utilisé),
# attend l'arrivée dans le niveau, déplace Astro et relève sur $Secondes s le temps processeur de chaque fil (nommé par
# GetThreadDescription). Résultat trié : % d'un cœur occupé par fil. Ferme proprement, restaure AstroBot.json.
param([string]$Niveau = 'underwater_aerial_garden', [hashtable]$Variables = @{}, [string]$Emulateur = 'Outils\KytyPS5_MC_install',
      [int]$Attente = 75, [int]$Secondes = 30, [string]$Etiquette = 'fils')
$r = if ($env:ASTROBOT_ROOT) { $env:ASTROBOT_ROOT } else { (Resolve-Path "$PSScriptRoot\..\..").Path }; $json = "$r\Jeu\AstroBot.json"; $pilote = "$r\Developpement\outils\pilote.ps1"
$res = "$r\Outils_Claude\work\fils-$Etiquette-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Fil {
  [DllImport("kernel32.dll")] public static extern IntPtr OpenThread(int a, bool i, int id);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern int GetThreadDescription(IntPtr h, out IntPtr d);
  [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
  public static string Nom(int id) { IntPtr h = OpenThread(0x0800, false, id); if (h == IntPtr.Zero) return "?";
    IntPtr d; string n = "?"; if (GetThreadDescription(h, out d) >= 0 && d != IntPtr.Zero) { n = Marshal.PtrToStringUni(d); LocalFree(d); }
    CloseHandle(h); return n; } }
"@
if (Get-Process kyty_emulator -ErrorAction SilentlyContinue) { throw 'kyty_emulator tourne déjà' }
$avant = [IO.File]::ReadAllText($json, [Text.Encoding]::UTF8)
try {
  $d = $avant | ConvertFrom-Json; $v = @{}; $d.variables.PSObject.Properties | ForEach-Object { $v[$_.Name] = $_.Value }
  foreach ($e in $Variables.GetEnumerator()) { $v[$e.Key] = $e.Value }
  $d | Add-Member -NotePropertyName variables -NotePropertyValue ([pscustomobject]$v) -Force
  $d | Add-Member -NotePropertyName emulateur -NotePropertyValue $Emulateur -Force
  [IO.File]::WriteAllText($json, ($d | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
  Start-Process "$r\Jeu\AstroBot.exe" -ArgumentList '--niveau', $Niveau
  Start-Sleep -Seconds 10; [IO.File]::WriteAllText($json, $avant, (New-Object Text.UTF8Encoding($false)))
  Start-Sleep -Seconds ($Attente - 10)
  $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue; if (-not $p) { throw 'le jeu ne tourne pas' }
  $job = Start-Job -ArgumentList $pilote, $Secondes -ScriptBlock { param($pil, $s) $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s + 5) { try { & $pil -Script 'maintenir W 3000; touche J 150; maintenir S 3000; maintenir A 2000; maintenir D 2000' | Out-Null } catch { Start-Sleep 1 } } }
  Start-Sleep 3
  $p.Refresh(); $a = @{}; foreach ($t in $p.Threads) { try { $a[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch {} }
  $t0 = Get-Date; Start-Sleep -Seconds $Secondes; $p.Refresh(); $dt = ((Get-Date) - $t0).TotalMilliseconds
  $lignes = foreach ($t in $p.Threads) { try { if ($a.ContainsKey($t.Id)) { $c = ($t.TotalProcessorTime.TotalMilliseconds - $a[$t.Id]) / $dt * 100
        if ($c -ge 0.5) { [pscustomobject]@{ pc = [Math]::Round($c, 1); id = $t.Id; nom = [Fil]::Nom($t.Id) } } } } catch {} }
  $total = ($lignes | Measure-Object pc -Sum).Sum
  "Fils de kyty_emulator ($Etiquette, $Niveau), $Secondes s en déplacement : total {0:N0} % d'un cœur ; titre : {1}" -f $total, ($p.MainWindowTitle -replace '^.*\] ', '') | Set-Content $res -Encoding UTF8
  $lignes | Sort-Object pc -Descending | ForEach-Object { '{0,6:N1} %  {1,-6} {2}' -f $_.pc, $_.id, $_.nom } | Add-Content $res
  Receive-Job $job -Wait -ErrorAction SilentlyContinue | Out-Null; Remove-Job $job -Force
} finally {
  $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue
  if ($p) { [void]$p.CloseMainWindow(); if (-not $p.WaitForExit(30000)) { Stop-Process -Id $p.Id -Force; 'arrêt forcé' } else { 'fermé proprement' } }
  [IO.File]::WriteAllText($json, $avant, (New-Object Text.UTF8Encoding($false)))
}
Get-Content $res
