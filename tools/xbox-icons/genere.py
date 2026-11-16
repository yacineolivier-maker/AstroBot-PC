# Icônes de boutons A/B/X/Y (dessin original : lettre dans un rond) pour remplacer les symboles PlayStation
# d'Astro Bot quand une manette Xbox est branchée. Écrit des .gnfp (en-tête GNF construit ici, texture 128x128
# 8_8_8_8 sRGB, linéaire, un seul niveau) dans <sortie>\data\prein\ui\gfx\, chargés par KYTY_APP0_OVERLAY.
# Usage : python genere.py <dossier de sortie> [--png]   (--png : aperçus PNG à côté, pour contrôle)
import os, struct, sys
from PIL import Image, ImageDraw, ImageFont

TAILLE = 128
# Correspondance de position : croix = A (bas), rond = B (droite), carré = X (gauche), triangle = Y (haut).
BOUTONS = {
    'A': ((96, 200, 64), ['ui_buuton_ps5_cross', 'nx_ui_btn_shapes_cross', 'nx_ui_btn_shapes_cross_2']),
    'B': ((235, 70, 60), ['ui_buuton_ps5_circle', 'nx_ui_btn_shapes_circle', 'nx_ui_btn_shapes_circle_2']),
    'X': ((60, 130, 235), ['ui_buuton_ps5_square', 'nx_ui_btn_shapes_square']),
    'Y': ((245, 200, 50), ['ui_buuton_ps5_triangle', 'nx_ui_btn_shapes_tri']),
}

def icone(lettre, couleur):
    s = 4  # suréchantillonnage pour des bords lisses
    im = Image.new('RGBA', (TAILLE * s, TAILLE * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    m = 6 * s
    d.ellipse([m, m, TAILLE * s - m, TAILLE * s - m], fill=(30, 30, 34, 255), outline=(245, 245, 245, 255), width=7 * s)
    police = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 78 * s)
    b = d.textbbox((0, 0), lettre, font=police)
    x = (TAILLE * s - (b[2] - b[0])) / 2 - b[0]
    y = (TAILLE * s - (b[3] - b[1])) / 2 - b[1]
    d.text((x, y), lettre, font=police, fill=couleur + (255,))
    im = im.resize((TAILLE, TAILLE), Image.LANCZOS)
    # Pixels transparents à zéro (sans couleur), pour que l'alpha prémultiplié ou non donne le même bord.
    px = [(r, g, b, a) if a else (0, 0, 0, 0) for (r, g, b, a) in im.getdata()]
    im.putdata(px)
    return im

def gnf(im):
    # T# PS5 (RDNA2), 8 mots : base 0 (le jeu la renseigne), format 130 = 8_8_8_8 sRGB, 128x128,
    # sélecteurs XYZW, niveaux 0..0, mode de tuile 0 (linéaire), type 2D ; max_mip 0.
    w = h = TAILLE
    f = [0] * 8
    f[1] = 0x10 | (130 << 20) | (((w - 1) & 3) << 30)
    f[2] = ((w - 1) >> 2) | ((h - 1) << 14) | 0x80000000
    f[3] = 0xFAC | (0 << 12) | (0 << 16) | (0 << 20) | (9 << 28)
    f[5] = 0
    f[7] = 0x10000                                           # taille des données
    entete = bytearray(0x10000)
    entete[0:4] = b'GNF '
    struct.pack_into('<I', entete, 4, 0xFFF8)
    entete[8:12] = bytes([5, 1, 1, 0])
    struct.pack_into('<I', entete, 0x10, 0x10000)            # début des données
    struct.pack_into('<I', entete, 0x18, 0x20000)            # taille du fichier
    struct.pack_into('<8I', entete, 0x28, *f)
    donnees = im.tobytes()                                   # RGBA, 4 octets par pixel, lignes de 512 octets
    assert len(donnees) == 0x10000
    return bytes(entete) + donnees

def main():
    sortie = sys.argv[1]
    png = '--png' in sys.argv
    dossier = os.path.join(sortie, 'data', 'prein', 'ui', 'gfx')
    os.makedirs(dossier, exist_ok=True)
    for lettre, (couleur, noms) in BOUTONS.items():
        im = icone(lettre, couleur)
        contenu = gnf(im)
        for n in noms:
            with open(os.path.join(dossier, n + '.gnfp'), 'wb') as fh:
                fh.write(contenu)
        if png:
            im.save(os.path.join(sortie, 'apercu-%s.png' % lettre))
    print('icônes écrites dans', dossier)

main()
