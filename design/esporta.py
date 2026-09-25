#!/usr/bin/env python3
"""Rigenera icone e favicon a partire dai sorgenti in design/.

    design/icone/icone.json  ->  design/icone/<nome>.svg   (una per icona)
                                 design/icone/sprite.svg   (tutte, come <symbol>,
                                                            piu' il marchio)
    design/marchio/*.svg     ->  conf/icone/               (PNG, .ico, favicon.svg,
                                                            site.webmanifest)

Il sorgente delle icone e' icone.json, non i file .svg: un'icona si cambia o
si aggiunge li', poi si rilancia questo script. I .svg singoli servono a
guardarle e a usarle fuori dalla dashboard; lo sprite e' quello che install.sh
mette dentro la pagina.

conf/icone/ e' ignorata da git (i binari cambiano da installazione a
installazione, vedi conf/icone/LEGGIMI.md): i PNG si rigenerano qui, non si
committano.

Uso:
    python design/esporta.py                  # icone + favicon
    python design/esporta.py --solo-icone     # niente PNG: non servono cairosvg e pillow
    python design/esporta.py --nome ttmux     # il nome che finisce nel webmanifest

Per i PNG servono cairosvg e pillow. Non il python di sistema: l'env conda del
progetto, per esempio
    conda create -n ttmux -c conda-forge python=3.12 cairosvg pillow
    conda run -n ttmux python design/esporta.py
"""
import argparse
import io
import json
import re
import shutil
import sys
from pathlib import Path

DESIGN = Path(__file__).resolve().parent
RADICE = DESIGN.parent
ICONE = DESIGN / 'icone'
MARCHIO = DESIGN / 'marchio'
USCITA = RADICE / 'conf' / 'icone'

# Gli attributi del tratto stanno sulla radice del file singolo e, nello
# sprite, sul CSS di .ico nella pagina: dentro i <symbol> ci sono solo i
# tracciati, cosi' lo spessore si puo' cambiare per dimensione (2 a 16 px,
# 1,9 a 20, 1,75 a 24) senza toccare le icone.
TESTA_SVG = ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
             'fill="none" stroke="currentColor" stroke-width="1.75" '
             'stroke-linecap="round" stroke-linejoin="round">')


def tracciati(icona):
    """I due tracciati di un'icona: d va col tratto, f e' pieno (currentColor)."""
    out = ''
    if icona['d']:
        out += f'<path d="{icona["d"]}"/>'
    if icona['f']:
        out += f'<path d="{icona["f"]}" fill="currentColor" stroke="none"/>'
    return out


def esporta_icone():
    icone = json.loads((ICONE / 'icone.json').read_text(encoding='utf-8'))
    nomi = [i['nome'] for i in icone]
    doppi = {n for n in nomi if nomi.count(n) > 1}
    if doppi:
        sys.exit(f'icone.json: nomi doppi {sorted(doppi)}')

    for i in icone:
        (ICONE / f'{i["nome"]}.svg').write_text(
            TESTA_SVG + f'<title>{i["etichetta"]}</title>' + tracciati(i) + '</svg>\n',
            encoding='utf-8', newline='\n')

    righe = ['<svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">']
    for i in icone:
        righe.append(f'  <symbol id="i-{i["nome"]}" viewBox="0 0 24 24">{tracciati(i)}</symbol>')
    # Il marchio viaggia con le icone, cosi' la pagina lo usa con
    # <use href="#marchio"> senza una seconda copia dei tracciati nel modello.
    # Neutro = color del contenitore, accento = --acc (i colori stanno in
    # style="" e non negli attributi: var() li' non e' garantito ovunque).
    # Sotto i 24 px si usa #marchio-piccolo, senza il prompt.
    for simbolo, file in (('marchio', 'marchio-inline.svg'), ('marchio-piccolo', 'marchio-piccolo-inline.svg')):
        testo = (MARCHIO / file).read_text(encoding='utf-8')
        tracciati_marchio = ''.join(re.findall(r'<path\b[^>]*/>', testo))
        if not tracciati_marchio:
            sys.exit(f'{file}: nessun <path> trovato')
        righe.append(f'  <symbol id="{simbolo}" viewBox="0 0 48 48">{tracciati_marchio}</symbol>')
    righe.append('</svg>')
    (ICONE / 'sprite.svg').write_text('\n'.join(righe) + '\n', encoding='utf-8', newline='\n')
    print(f'{len(icone)} icone + marchio -> {ICONE.relative_to(RADICE)}/*.svg e sprite.svg')


def esporta_favicon(nome):
    try:
        import cairosvg
        from PIL import Image
    except ImportError as err:
        sys.exit(f'per i PNG servono cairosvg e pillow ({err}); oppure --solo-icone')

    USCITA.mkdir(parents=True, exist_ok=True)

    def png(sorgente, lato):
        dati = cairosvg.svg2png(url=str(MARCHIO / sorgente), output_width=lato, output_height=lato)
        return Image.open(io.BytesIO(dati)).convert('RGBA')

    # Icona app: fondo pieno a tutto quadrato, iOS e Android arrotondano da se'.
    png('icona-app.svg', 180).save(USCITA / 'apple-touch-icon.png')
    png('icona-app.svg', 192).save(USCITA / 'android-chrome-192x192.png')
    png('icona-app.svg', 512).save(USCITA / 'android-chrome-512x512.png')
    # Favicon PNG: marchio piccolo su un quadrato scuro arrotondato. Si vede su
    # una scheda chiara come su una scura, anche dove l'SVG non arriva.
    png('favicon-png.svg', 32).save(USCITA / 'favicon-32x32.png')
    png('favicon-png.svg', 16).save(USCITA / 'favicon-16x16.png')
    png('favicon-png.svg', 48).save(USCITA / 'favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])
    # favicon.svg si adatta da solo al tema del sistema (prefers-color-scheme).
    shutil.copyfile(MARCHIO / 'favicon.svg', USCITA / 'favicon.svg')

    # Percorsi relativi: il manifest funziona uguale col vhost suo e sotto un
    # PREFISSO, perche' si risolvono rispetto all'URL del manifest stesso.
    manifest = {
        'name': nome,
        'short_name': nome,
        'icons': [
            {'src': 'android-chrome-192x192.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'any'},
            {'src': 'android-chrome-512x512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'any'},
            {'src': 'android-chrome-512x512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'maskable'},
        ],
        'start_url': './',
        'scope': './',
        'display': 'standalone',
        'theme_color': '#121212',
        'background_color': '#121212',
    }
    (USCITA / 'site.webmanifest').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n',
                                             encoding='utf-8', newline='\n')
    print(f'favicon, icona app e site.webmanifest -> {USCITA.relative_to(RADICE)}/')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--solo-icone', action='store_true', help='rigenera solo i .svg delle icone e lo sprite')
    ap.add_argument('--nome', default='tmuxify', help='nome dell\'app nel webmanifest (default: tmuxify)')
    a = ap.parse_args()
    esporta_icone()
    if not a.solo_icone:
        esporta_favicon(a.nome)


if __name__ == '__main__':
    main()
