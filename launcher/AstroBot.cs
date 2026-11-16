// Lanceur Astro Bot (sans console), pour un raccourci, un double-clic ou un lanceur de jeux.
// - reglages durables dans Jeu\AstroBot.json (cree avec les valeurs par defaut s'il manque) ;
// - variables KYTY_* de Jeu\KytyPS5_U59\u59-preset.json ; TEMP/TMP sous Outils_Claude\work ; cwd Jeu\KytyPS5_U59 ;
// - kyty_emulator.exe --game Rom\PPSA21567-1.019 --shader-validation false + manette, micro, volumes ;
// - journaux : Jeu\KytyPS5_U59\journaux\console-<date>.txt (sortie de l'emulateur),
//   fps-<date>.csv (une ligne par seconde) et fps-historique.csv (bilan de chaque partie).
// Compilation : csc /target:winexe /out:Jeu\AstroBot.exe /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll
//               Developpement\lanceur\AstroBot.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

static class AstroBot
{
    // Racine du portage : ASTROBOT_ROOT si defini, sinon le dossier parent de celui de l'exe (Jeu\AstroBot.exe).
    static readonly string Racine = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ASTROBOT_ROOT"))
        ? Environment.GetEnvironmentVariable("ASTROBOT_ROOT")
        : Path.GetDirectoryName(Path.GetDirectoryName(Application.ExecutablePath));
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    // Reglages par defaut (manette Xbox : ni pave tactile, ni gyroscope, ni micro, ni haut-parleur).
    const string ReglagesParDefaut = @"{
  ""_aide"": ""Reglages d'Astro Bot (lus a chaque lancement). Voir docs\\MANETTE.md."",
  ""manette"": {
    ""Cross"": ""South"", ""Circle"": ""East"", ""Square"": ""West"", ""Triangle"": ""North"",
    ""Options"": ""Start"", ""L1"": ""LeftShoulder"", ""R1"": ""RightShoulder"",
    ""L2"": ""LeftTrigger"", ""R2"": ""RightTrigger"", ""L3"": ""LeftStick"", ""R3"": ""RightStick"",
    ""Up"": ""DpadUp"", ""Down"": ""DpadDown"", ""Left"": ""DpadLeft"", ""Right"": ""DpadRight"",
    ""TouchPad"": ""Back"",
    ""TouchPadMode"": ""Guide""
  },
  ""micro"": """",
  ""volumeHautParleurManette"": 100,
  ""vibration"": 100,
  ""pleinEcran"": false,
  ""langue"": ""auto"",
  ""icones"": ""auto"",
  ""largeurEcran"": 1280,
  ""hauteurEcran"": 720,
  ""journalFps"": true,
  ""avantJeu"": """",
  ""apresJeu"": """",
  ""_mode30"": ""Mode qualite 30 i/s (a valider) : patchJeu = Developpement\patches\jeu\PPSA21567_01.019.000_logique30.json et frequenceVblank = 30"",
  ""patchJeu"": """",
  ""frequenceVblank"": 60,
  ""argumentsSupplementaires"": []
}";

    [STAThread]
    static int Main(string[] extra)
    {
        string emu = Path.Combine(Racine, @"Jeu\KytyPS5_U59");
        string exe = Path.Combine(emu, "kyty_emulator.exe");
        string jeu = Path.Combine(Racine, @"Rom\PPSA21567-1.019");
        string work = Path.Combine(Racine, @"Outils_Claude\work");
        string journaux = Path.Combine(emu, "journaux");
        string fichierReglages = Path.Combine(Racine, @"Jeu\AstroBot.json");
        try
        {
            if (Process.GetProcessesByName("kyty_emulator").Length > 0)
            {
                MessageBox.Show("Astro Bot (kyty_emulator) est deja lance.", "Astro Bot");
                return 1;
            }
            Directory.CreateDirectory(work);
            Directory.CreateDirectory(journaux);
            if (!File.Exists(fichierReglages)) File.WriteAllText(fichierReglages, ReglagesParDefaut, new UTF8Encoding(false));
            var reglages = (Dictionary<string, object>)new JavaScriptSerializer().DeserializeObject(File.ReadAllText(fichierReglages));
            // « emulateur » : autre dossier d'emulateur (relatif a la racine), ex. la version de diagnostic.
            // Les journaux restent dans Jeu\KytyPS5_U59\journaux.
            string autreEmu = Texte(reglages, "emulateur");
            if (autreEmu != "")
            {
                emu = Path.Combine(Racine, autreEmu);
                exe = Path.Combine(emu, "kyty_emulator.exe");
                if (!File.Exists(exe)) { MessageBox.Show("Emulateur introuvable : " + exe, "Astro Bot"); return 1; }
            }

            var psi = new ProcessStartInfo(exe)
            {
                WorkingDirectory = emu, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            };
            psi.EnvironmentVariables["TEMP"] = work;
            psi.EnvironmentVariables["TMP"] = work;
            // Reglages propres a la version U59 ; les autres versions (officielle, forks) n'en ont pas et gardent les leurs.
            string presetPath = Path.Combine(emu, "u59-preset.json");
            if (File.Exists(presetPath))
            {
                var preset = (Dictionary<string, object>)new JavaScriptSerializer().DeserializeObject(File.ReadAllText(presetPath));
                foreach (var kv in preset) psi.EnvironmentVariables[kv.Key] = Convert.ToString(kv.Value, Inv);
            }
            // Surcharges de variables KYTY_* (essais de reglages sans toucher a u59-preset.json).
            object vars;
            if (reglages.TryGetValue("variables", out vars) && vars is Dictionary<string, object>)
                foreach (var kv in (Dictionary<string, object>)vars) psi.EnvironmentVariables[kv.Key] = Convert.ToString(kv.Value, Inv);

            var a = new List<string> { "--game", jeu };
            // U59 : « --shader-validation false » ; version officielle : simple interrupteur (absent = coupe).
            if (File.Exists(presetPath)) { a.Add("--shader-validation"); a.Add("false"); }
            // Version officielle : l'emulation des instructions AMD (SSE4a...) n'est pas automatique sur un processeur Intel.
            else a.Add("--amd-cpu");
            // Une seule entree Pad: remplace toutes les correspondances par defaut : la liste est donc complete.
            object manette;
            if (reglages.TryGetValue("manette", out manette) && manette is Dictionary<string, object>)
                foreach (var kv in (Dictionary<string, object>)manette)
                    if (!string.IsNullOrEmpty(Convert.ToString(kv.Value))) { a.Add("--keymap"); a.Add("Pad:" + kv.Key + "=" + kv.Value); }
            string micro = Texte(reglages, "micro");
            if (micro != "") { a.Add("--mic"); a.Add(micro); }
            // Option propre a la version U59 : la version officielle de KytyPS5 s'arrete sur une option inconnue.
            // A 100 (defaut des deux versions), on ne la passe pas.
            int volumePad = Entier(reglages, "volumeHautParleurManette", 100);
            if (volumePad != 100) { a.Add("--audio-pad-speaker-volume"); a.Add(volumePad.ToString(Inv)); }
            a.Add("--controller-vibration"); a.Add(Entier(reglages, "vibration", 100).ToString(Inv));
            if (Vrai(reglages, "pleinEcran", false)) a.Add("--fullscreen");
            // Langue de la console virtuelle : "auto" (defaut) = langue d'affichage de Windows, sinon code PS (0-29) ou nom (fr-FR).
            int langue = LangueConsole(Texte(reglages, "langue"));
            a.Add("--console-language"); a.Add(langue.ToString(Inv));
            // Taille de sortie video du jeu (la console virtuelle) : 1280x720 par defaut dans l'emulateur.
            int largeur = Entier(reglages, "largeurEcran", 1280), hauteur = Entier(reglages, "hauteurEcran", 720);
            if (largeur != 1280 || hauteur != 720) { a.Add("--screen-width"); a.Add(largeur.ToString(Inv)); a.Add("--screen-height"); a.Add(hauteur.ToString(Inv)); }
            // Mode 30 i/s : patch de jeu (frequence cible du moteur 30) + synchronisation verticale virtuelle a 30 Hz.
            string patchJeu = Texte(reglages, "patchJeu");
            if (patchJeu != "") { a.Add("--game-patch"); a.Add(Path.IsPathRooted(patchJeu) ? patchJeu : Path.Combine(Racine, patchJeu)); }
            int vblank = Entier(reglages, "frequenceVblank", 60);
            if (vblank != 60) { a.Add("--vblank-frequency"); a.Add(vblank.ToString(Inv)); }
            object sup;
            if (reglages.TryGetValue("argumentsSupplementaires", out sup) && sup is object[])
                foreach (object o in (object[])sup) a.Add(Convert.ToString(o, Inv));
            // --niveau <fichier de product_levels.xml> : args.txt de remplacement (arguments d'origine + -lvl), lu par
            // l'emulateur via KYTY_APP0_OVERLAY (correctif 0002) ; le dossier du jeu n'est pas modifie.
            var reste = new List<string>(extra);
            int iN = reste.IndexOf("--niveau");
            string overlay = Path.Combine(emu, "overlay");
            string argsRemplace = Path.Combine(overlay, "args.txt");
            if (File.Exists(argsRemplace)) File.Delete(argsRemplace);   // pas de niveau impose par defaut
            bool surcouche = false;
            if (iN >= 0 && iN + 1 < reste.Count)
            {
                Directory.CreateDirectory(overlay);
                string origine = File.ReadAllText(Path.Combine(jeu, "args.txt")).Trim();
                File.WriteAllText(argsRemplace, origine + " -lvl " + reste[iN + 1], new UTF8Encoding(false));
                surcouche = true;
                reste.RemoveRange(iN, 2);
            }
            // Icones de boutons : "auto" (defaut) = A/B/X/Y si une manette XInput (Xbox) est branchee, "xbox", "ps".
            // Les textures de remplacement (Jeu\icones-xbox, dessin original) sont copiees dans la surcouche.
            string sourceIcones = Path.Combine(Racine, @"Jeu\icones-xbox");
            string reglageIcones = Texte(reglages, "icones").ToLowerInvariant();
            bool xbox = reglageIcones == "xbox" || ((reglageIcones == "" || reglageIcones == "auto") && ManetteXInput());
            foreach (string f in Directory.Exists(sourceIcones) ? Directory.GetFiles(sourceIcones, "*.gnfp", SearchOption.AllDirectories) : new string[0])
            {
                string cible = Path.Combine(overlay, f.Substring(sourceIcones.Length + 1));
                if (xbox) { Directory.CreateDirectory(Path.GetDirectoryName(cible)); File.Copy(f, cible, true); surcouche = true; }
                else if (File.Exists(cible)) File.Delete(cible);
            }
            if (surcouche) psi.EnvironmentVariables["KYTY_APP0_OVERLAY"] = overlay;
            a.AddRange(reste);
            psi.Arguments = string.Join(" ", a.Select(Citer));

            string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            // Commandes facultatives avant/apres (reglages avantJeu/apresJeu) la partie et fichier d'etat pendant la partie.
            string etat = Path.Combine(Racine, @"Jeu\partie-en-cours.json");
            File.WriteAllText(etat, "{\"jeu\": \"Astro Bot\", \"debut\": \"" + DateTime.Now.ToString("s") + "\", \"pid_lanceur\": " + Process.GetCurrentProcess().Id + "}", new UTF8Encoding(false));
            Crochet(Texte(reglages, "avantJeu"), journaux, "avant");
            string log = Path.Combine(journaux, "console-" + stamp + ".txt");
            using (var w = new StreamWriter(log, false, new UTF8Encoding(false)) { AutoFlush = true })
            {
                object verrou = new object();
                w.WriteLine("Lancement : kyty_emulator.exe " + psi.Arguments);
                w.WriteLine("Icones de boutons : " + (xbox ? "A/B/X/Y (manette XInput)" : "PlayStation"));
                var p = new Process { StartInfo = psi };
                p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (verrou) w.WriteLine(e.Data); };
                p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (verrou) w.WriteLine(e.Data); };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                JournalFps fps = Vrai(reglages, "journalFps", true) ? new JournalFps(p, journaux, stamp) : null;
                p.WaitForExit();
                p.WaitForExit(); // vide les tampons asynchrones
                string bilan = fps != null ? fps.Terminer(p.ExitCode) : "";
                lock (verrou) { if (bilan != "") w.WriteLine(bilan); w.WriteLine("Code de sortie : " + p.ExitCode); }
                try { File.Delete(etat); } catch { }
                Crochet(Texte(reglages, "apresJeu"), journaux, "apres");
                return p.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Lancement d'Astro Bot impossible :\n" + ex.Message, "Astro Bot");
            return 2;
        }
    }

    // Lance une commande du mode jeu (cmd /c), attend au plus 60 s, et note le resultat ; un echec ne bloque pas le jeu.
    static void Crochet(string commande, string journaux, string quand)
    {
        if (string.IsNullOrEmpty(commande)) return;
        string trace = Path.Combine(journaux, "mode-jeu.txt");
        try
        {
            var c = Process.Start(new ProcessStartInfo("cmd.exe", "/c " + commande) { UseShellExecute = false, CreateNoWindow = true });
            bool fini = c.WaitForExit(60000);
            File.AppendAllText(trace, DateTime.Now.ToString("s") + " " + quand + " : " + commande + " -> " + (fini ? "code " + c.ExitCode : "toujours en cours apres 60 s") + Environment.NewLine);
        }
        catch (Exception ex) { File.AppendAllText(trace, DateTime.Now.ToString("s") + " " + quand + " : echec " + ex.Message + Environment.NewLine); }
    }

    static string Citer(string s) { return s.IndexOfAny(new[] { ' ', '"', '\t' }) < 0 && s != "" ? s : "\"" + s.Replace("\"", "\\\"") + "\""; }
    // Ordre des langues de la console (identique a common/localization.cpp de KytyPS5).
    static readonly string[] Langues = { "ja-JP", "en-US", "fr-FR", "es-ES", "de-DE", "it-IT", "nl-NL", "pt-PT",
        "ru-RU", "ko-KR", "zh-Hant", "zh-Hans", "fi-FI", "sv-SE", "da-DK", "no-NO", "pl-PL", "pt-BR", "en-GB", "tr-TR",
        "es-419", "ar-AE", "fr-CA", "cs-CZ", "hu-HU", "el-GR", "ro-RO", "th-TH", "vi-VN", "id-ID" };
    static int LangueConsole(string reglage)
    {
        int n;
        if (int.TryParse(reglage, NumberStyles.Integer, Inv, out n) && n >= 0 && n < Langues.Length) return n;
        string nom = (reglage == "" || reglage.Equals("auto", StringComparison.OrdinalIgnoreCase)) ? CultureInfo.CurrentUICulture.Name : reglage;
        int i = Array.FindIndex(Langues, l => l.Equals(nom, StringComparison.OrdinalIgnoreCase));
        if (i >= 0) return i;
        if (nom.StartsWith("zh", StringComparison.OrdinalIgnoreCase)) return nom.Contains("Hant") || nom.EndsWith("TW") || nom.EndsWith("HK") ? 10 : 11;
        if (nom.StartsWith("es-", StringComparison.OrdinalIgnoreCase) && !nom.Equals("es-ES", StringComparison.OrdinalIgnoreCase)) return 20;
        if (nom.StartsWith("nb", StringComparison.OrdinalIgnoreCase) || nom.StartsWith("nn", StringComparison.OrdinalIgnoreCase)) return 15;
        string deux = nom.Split('-')[0];
        i = Array.FindIndex(Langues, l => l.Split('-')[0].Equals(deux, StringComparison.OrdinalIgnoreCase));
        return i >= 0 ? i : 1;
    }
    [System.Runtime.InteropServices.DllImport("xinput1_4.dll")]
    static extern int XInputGetState(int index, byte[] state);
    // Une manette XInput (Xbox, ou une manette presentee comme telle) est-elle branchee ?
    static bool ManetteXInput()
    {
        try { var etat = new byte[16]; for (int i = 0; i < 4; i++) if (XInputGetState(i, etat) == 0) return true; }
        catch (Exception) { }
        return false;
    }
    static string Texte(Dictionary<string, object> d, string k) { object v; return d.TryGetValue(k, out v) && v != null ? Convert.ToString(v, Inv) : ""; }
    static int Entier(Dictionary<string, object> d, string k, int def) { object v; return d.TryGetValue(k, out v) && v != null ? Convert.ToInt32(v, Inv) : def; }
    static bool Vrai(Dictionary<string, object> d, string k, bool def) { object v; return d.TryGetValue(k, out v) && v is bool ? (bool)v : def; }
}

// Releve d'images par seconde : chaque seconde, lit le titre de la fenetre de l'emulateur (« frame: N, fps: F »)
// et la memoire du processus. En fin de partie : bilan (moyenne, mediane, 1 % bas, gels) dans fps-historique.csv.
class JournalFps
{
    readonly Process p; readonly string csv, historique, stamp;
    readonly List<double> fps = new List<double>();
    readonly Stopwatch montre = Stopwatch.StartNew();
    readonly Thread fil; volatile bool fin;
    long premiereImage = -1, derniereImage = -1; double tPremiere, tDerniere;
    int gelEnCours, plusLongGel, gels;
    static readonly Regex Titre = new Regex(@"frame:\s*(\d+),\s*fps:\s*(\d+(?:\.\d+)?)");
    static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public JournalFps(Process p, string dossier, string stamp)
    {
        this.p = p; this.stamp = stamp;
        csv = Path.Combine(dossier, "fps-" + stamp + ".csv");
        historique = Path.Combine(dossier, "fps-historique.csv");
        File.WriteAllText(csv, "heure;secondes;image;fps;ram_mo\r\n");
        fil = new Thread(Boucle) { IsBackground = true };
        fil.Start();
    }

    void Boucle()
    {
        while (!fin)
        {
            Thread.Sleep(1000);
            try
            {
                p.Refresh();
                if (p.HasExited) break;
                Match m = Titre.Match(p.MainWindowTitle ?? "");
                if (!m.Success) continue;          // fenetre pas encore creee
                long image = long.Parse(m.Groups[1].Value, Inv);
                double f = double.Parse(m.Groups[2].Value, Inv);
                double t = montre.Elapsed.TotalSeconds;
                if (premiereImage < 0) { premiereImage = image; tPremiere = t; }
                derniereImage = image; tDerniere = t;
                lock (fps) fps.Add(f);
                if (f < 1) { gelEnCours++; if (gelEnCours == 1) gels++; plusLongGel = Math.Max(plusLongGel, gelEnCours); } else gelEnCours = 0;
                File.AppendAllText(csv, string.Format(Inv, "{0:HH:mm:ss};{1:0};{2};{3:0};{4}\r\n",
                    DateTime.Now, t, image, f, p.WorkingSet64 / (1024 * 1024)));
            }
            catch { /* processus en fin de vie */ }
        }
    }

    public string Terminer(int code)
    {
        fin = true; fil.Join(2000);
        List<double> v; lock (fps) v = fps.OrderBy(x => x).ToList();
        if (v.Count == 0) return "Bilan fps : aucune mesure.";
        double moyenne = (tDerniere > tPremiere) ? (derniereImage - premiereImage) / (tDerniere - tPremiere) : v.Average();
        double mediane = v[v.Count / 2];
        double bas1 = v.Take(Math.Max(1, v.Count / 100)).Average();
        double s55 = 100.0 * v.Count(x => x >= 55) / v.Count, s30 = 100.0 * v.Count(x => x < 30) / v.Count;
        if (!File.Exists(historique))
            File.WriteAllText(historique, "partie;duree_s;fps_moyen;fps_median;fps_1pc_bas;pct_ge55;pct_lt30;gels;plus_long_gel_s;code_sortie\r\n");
        File.AppendAllText(historique, string.Format(Inv, "{0};{1:0};{2:0.0};{3:0};{4:0.0};{5:0.0};{6:0.0};{7};{8};{9}\r\n",
            stamp, v.Count, moyenne, mediane, bas1, s55, s30, gels, plusLongGel, code));
        return string.Format(Inv, "Bilan fps : {0} s mesurees, moyenne {1:0.0}, mediane {2:0}, 1 % bas {3:0.0}, >=55 : {4:0.0} %, <30 : {5:0.0} %, gels {6} (plus long {7} s).",
            v.Count, moyenne, mediane, bas1, s55, s30, gels, plusLongGel);
    }
}
