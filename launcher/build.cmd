@echo off
rem Builds AstroBot.exe with the C# compiler that ships with Windows (.NET Framework 4).
rem Put the exe in <root>\Jeu\ : the launcher takes the folder above it as the port root (or set ASTROBOT_ROOT).
"%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /out:AstroBot.exe /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "%~dp0AstroBot.cs"
