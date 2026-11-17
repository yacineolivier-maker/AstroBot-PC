r"""(Published with the AstroBot-PC tools; French output.) Bilan d'une ou plusieurs sessions du journal de fluidité (KYTY_FLUIDITE=1).

Lit <dossier>\journal.csv (séparateur ;, décimales à virgule), regroupe les baisses par endroit : même fichier de
niveau récent et positions de caméra à moins de <rayon> unités, puis classe les endroits par gravité
(durée sous le seuil × manque d'i/s).

Les noms de niveaux viennent de la liste du jeu (data\prein\product_levels.xml, lue sur place, jamais copiée) :
le dossier levels\<fichier>\ d'un fichier récemment ouvert donne le niveau.

Usage : python -I fluidite-bilan.py <dossier de session ou dossier _Fluidite> [rayon=5] [dossier du jeu]
"""
import csv
import os
import math
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

JEU = os.environ.get("ASTROBOT_GAME_DIR", "")  # game folder holding data\prein (or 3rd argument)


def noms_niveaux(jeu):
    noms = {}
    for liste in sorted(pathlib.Path(jeu, "data", "prein").glob("*_levels.xml")):
        try:
            racine = ET.parse(liste).getroot()
        except ET.ParseError:
            continue
        for niveau in racine.iter("Level"):
            fichier, nom = niveau.findtext("File"), niveau.findtext("Name")
            if fichier and nom:
                noms.setdefault(fichier.strip().lower(), nom.strip())
    return noms


def niveau_de(fichiers, noms):
    for chemin in fichiers.split(" | "):
        m = re.search(r"levels/([^/]+)/", chemin.replace("\\", "/"), re.I)
        if m:
            return noms.get(m.group(1).lower(), m.group(1))
    return next((p for p in fichiers.split(" | ") if p), "?")


def nombre(texte):
    try:
        return float(texte.replace(",", "."))
    except ValueError:
        return None


def lire(dossier, noms):
    lignes = []
    for journal in sorted(pathlib.Path(dossier).rglob("journal.csv")):
        with open(journal, encoding="utf-8-sig", newline="") as f:
            for l in csv.DictReader(f, delimiter=";"):
                l["session"] = journal.parent.name
                cam = [nombre(v) for v in (l.get("camera") or "").split()]
                l["pos"] = tuple(cam[0:3]) if len(cam) >= 7 and None not in cam[0:3] else None
                l["dir"] = tuple(cam[4:7]) if len(cam) >= 7 and None not in cam[4:7] else None
                l["niveau"] = niveau_de(l.get("fichiers_recents") or "", noms)
                lignes.append(l)
    return lignes


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    rayon = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
    noms = noms_niveaux(sys.argv[3] if len(sys.argv) > 3 else JEU)
    lignes = [l for l in lire(sys.argv[1], noms) if l["n"] not in ("S",)]
    endroits = []
    for l in lignes:
        if l["type"] in ("arret", "session"):  # chargements, menus, pauses
            continue
        duree = nombre(l["duree_s"]) or 0.0
        ips = nombre(l["ips_min_1s"]) or 30.0
        poids = duree * max(0.0, 30.0 - ips) + (1.0 if l["type"] in ("pic", "marque") else 0.0)
        for e in endroits:
            if e["niveau"] != l["niveau"]:
                continue
            if l["pos"] is None or e["pos"] is None or math.dist(l["pos"], e["pos"]) <= rayon:
                e["lignes"].append(l)
                e["poids"] += poids
                break
        else:
            endroits.append({"niveau": l["niveau"], "pos": l["pos"], "lignes": [l], "poids": poids})
    endroits.sort(key=lambda e: -e["poids"])
    print(f"{len(lignes)} lignes, {len(endroits)} endroits (rayon {rayon})")
    for i, e in enumerate(endroits[:30], 1):
        ips = [nombre(l["ips_min_1s"]) for l in e["lignes"] if nombre(l["ips_min_1s"]) is not None]
        pos = " ".join(f"{v:.1f}" for v in e["pos"]) if e["pos"] else "?"
        d = e["lignes"][0]["dir"]
        dirs = " ".join(f"{v:.2f}" for v in d) if d else "?"
        images = " ".join(x for l in e["lignes"] for x in (l.get("vignettes") or "").split())[:120]
        causes = {}
        for l in e["lignes"]:
            c = l.get("cause") or "?"
            causes[c] = causes.get(c, 0) + 1
        cause = ", ".join(f"{c} x{n}" for c, n in sorted(causes.items(), key=lambda x: -x[1]))
        rapports = sum(1 for l in e["lignes"] if l.get("rapport_gpu") == "oui")
        print(f"{i:2}. poids {e['poids']:6.1f} | {len(e['lignes'])} fois | i/s mini {min(ips) if ips else '-'} | "
              f"cause {cause} | rapports GPU {rapports}\n    niveau {e['niveau']} | pos {pos} | dir {dirs}\n"
              f"    {e['lignes'][0]['session']} : {images}")


if __name__ == "__main__":
    main()
