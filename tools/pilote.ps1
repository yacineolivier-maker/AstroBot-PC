# Pilote de test d'Astro Bot (kyty_emulator) : touches simulees et captures de la fenetre du jeu seule.
# Usage : pilote.ps1 -Script "touche J 150; attendre 2000; capture titre-apres-J; maintenir D 1500; capture x"
#   touche <TOUCHE> [ms]      appui bref (ms = duree d'appui, 120 par defaut)
#   maintenir <TOUCHE> <ms>   appui long
#   combo <T1+T2> <ms>        plusieurs touches ensemble (ex. D+J 800 : avancer en sautant)
#   attendre <ms>
#   capture <nom>             PNG de la zone client dans Jeu\KytyPS5_U59\captures\pilote\<nom>.png
#   titre                     affiche le titre (fps, frame)
# Touches clavier de l'emulateur : J=Croix K=Carre I=Triangle L=Rond Q=L1 E=R1 Z=L2 C=R2 Entree=Options
#   fleches = croix directionnelle ; stick gauche W/A/S/D (QWERTY) ; stick droit = souris (voir hostInput.cpp).
param([Parameter(Mandatory)][string]$Script)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Pil {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int l, int ht, uint f);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; }
  [StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref P p);
}
"@
$vk = @{ 'J'=0x4A;'K'=0x4B;'I'=0x49;'L'=0x4C;'Q'=0x51;'E'=0x45;'Z'=0x5A;'C'=0x43;'W'=0x57;'A'=0x41;'S'=0x53;'D'=0x44;'F'=0x46;'H'=0x48;'T'=0x54;'G'=0x47;'RETOUR'=0x08;'TAB'=0x09;
         'ENTREE'=0x0D;'HAUT'=0x26;'BAS'=0x28;'GAUCHE'=0x25;'DROITE'=0x27;'ECHAP'=0x1B;'F2'=0x71;'MAJ'=0xA0;'CTRL'=0xA2 }
function Fenetre { $p = Get-Process kyty_emulator -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) { throw "kyty_emulator ne tourne pas" }; $p.Refresh(); return $p }
# Met le jeu devant (au-dessus de tout) ; refuse d'envoyer une touche s'il n'a pas le focus,
# pour ne jamais taper dans une autre fenetre.
function Devant($h) {
  for ($i = 0; $i -lt 5 -and [Pil]::GetForegroundWindow() -ne $h; $i++) {
    [void][Pil]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0003)   # HWND_TOPMOST, sans deplacer ni redimensionner
    [Pil]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [Pil]::keybd_event(0x12,0,2,[UIntPtr]::Zero)
    [void][Pil]::SetForegroundWindow($h); Start-Sleep -Milliseconds 200 }
  if ([Pil]::GetForegroundWindow() -ne $h) { throw "le jeu n'a pas le focus : touche non envoyee" } }
function Bas($t)  { $k=[byte]$vk[$t]; $ext = if ($k -ge 0x25 -and $k -le 0x28) {1} else {0}
  [Pil]::keybd_event($k,[byte][Pil]::MapVirtualKey($k,0),$ext,[UIntPtr]::Zero) }
function Haut($t) { $k=[byte]$vk[$t]; $ext = if ($k -ge 0x25 -and $k -le 0x28) {1} else {0}
  [Pil]::keybd_event($k,[byte][Pil]::MapVirtualKey($k,0),2 -bor $ext,[UIntPtr]::Zero) }
$dir = "$(if ($env:ASTROBOT_ROOT) { $env:ASTROBOT_ROOT } else { (Resolve-Path "$PSScriptRoot\..\..").Path })\Jeu\KytyPS5_U59\captures\pilote"; New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($ligne in ($Script -split ';')) {
  $m = $ligne.Trim() -split '\s+'; if (-not $m[0]) { continue }
  $p = Fenetre; $h = $p.MainWindowHandle
  switch ($m[0].ToLower()) {
    'touche'    { Devant $h; $t=$m[1].ToUpper(); $d = if ($m.Count -gt 2) {[int]$m[2]} else {120}; Bas $t; Start-Sleep -Milliseconds $d; Haut $t }
    'maintenir' { Devant $h; $t=$m[1].ToUpper(); Bas $t; Start-Sleep -Milliseconds ([int]$m[2]); Haut $t }
    'combo'     { Devant $h; $ts=$m[1].ToUpper() -split '\+'; $ts | % { Bas $_ }; Start-Sleep -Milliseconds ([int]$m[2]); $ts | % { Haut $_ } }
    'attendre'  { Start-Sleep -Milliseconds ([int]$m[1]) }
    'titre'     { $p.MainWindowTitle -replace '^.*\] ', '' }
    'capture'   { Devant $h; Start-Sleep -Milliseconds 100
      $r = New-Object Pil+R; [void][Pil]::GetClientRect($h,[ref]$r); $o = New-Object Pil+P; [void][Pil]::ClientToScreen($h,[ref]$o)
      $bmp = New-Object Drawing.Bitmap ([Math]::Max(1,$r.Ri)), ([Math]::Max(1,$r.B)); $g = [Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($o.X, $o.Y, 0, 0, $bmp.Size); $f = Join-Path $dir "$($m[1]).png"; $bmp.Save($f); $g.Dispose(); $bmp.Dispose(); $f }
    default { throw "action inconnue : $ligne" }
  }
}
