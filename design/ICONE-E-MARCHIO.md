# Icone e marchio — il lavoro da fare

Brief per Claude Code. Tutto quello che serve sta in questa cartella (`design/`)
e in `conf/icone/`. La tavola visiva di riferimento è il canvas “TMUXIFY — marchio e
icone” (https://claude.ai/artifact/EH83ZBu6KiZW8u6QceDunH, privato: lo apre Roberto).
Questo file basta anche senza.

**Cosa si ottiene.** La dashboard (`conf/index.html.tmpl`) smette di usare Bootstrap
Icons da CDN e usa un set di icone suo, in linea nella pagina. In più ha il
marchio nuovo (favicon, icona app), le icone che mostrano lo stato (griglia, barra
tmux, congelato) e una spia di connessione su ogni tab. Il comportamento non
cambia: cambiano icone, raggruppamento della testata e alcuni stati visibili.

---

## 1. Decisioni prese

| cosa | decisione |
|---|---|
| Marchio | Direzione **A · Pannelli**: tre pannelli arrotondati; la T è lo spazio vuoto fra loro. In alto la barra dei tab, sotto due terminali; quello di sinistra è nell'accento e porta il prompt `>_`. |
| Colori del marchio | Neutro `#e8ebe9` + accento `#4fae8c` su scuro; neutro `#1b201e` + accento `#3b8369` (accento scurito del 25 %) su chiaro. |
| Accento della dashboard | Invariato: `--acc: #4fae8c`, `--acc-fondo: #14261f`, `--acc-bordo: #2b5145`. Un solo accento per tutto ciò che è “acceso”. |
| Colori di stato | Connesso = `var(--acc)`; si riconnette = `#d4a24c`; scollegato = `#e06c6c`. Le tre spie differiscono anche nella **forma** (pieno / tratteggiato / barrato), non solo nel colore. |
| Icone | Set proprio, 35 icone, disegnate su griglia 24. Sostituiscono Bootstrap Icons e i bottoni fatti di lettere (A›a, a›A). |
| Consegna delle icone | Sprite `<symbol>` messo nella pagina da `install.sh` al posto di un segnaposto `@SPRITE@`. Stesso principio di `@LICENZA@`: una copia a mano nel modello si allontanerebbe dal sorgente al primo ritocco. |
| Nome | Sul marchio c'è “tmuxify”, ma per ora compare **solo** in `site.webmanifest`. `TITOLO` resta configurabile come oggi. Vedi §8. |

---

## 2. I file

```
design/
  ICONE-E-MARCHIO.md          questo file
  esporta.py                  rigenera icone/*.svg, sprite.svg e i file di conf/icone/
  icone/
    icone.json                SORGENTE delle icone: nome, etichetta, gruppo, cosa sostituisce, tracciati
    sprite.svg                tutte le icone come <symbol id="i-NOME">, più #marchio e
                              #marchio-piccolo: va nella pagina
    <nome>.svg                una per icona, 24×24, currentColor (per guardarle e usarle altrove)
  marchio/
    marchio.svg               marchio completo, per fondi scuri, sfondo trasparente
    marchio-chiaro.svg        per fondi chiari
    marchio-piccolo.svg       sotto i 24 px: senza prompt (per fondi scuri)
    marchio-piccolo-chiaro.svg
    marchio-inline.svg        sorgente di #marchio nello sprite: neutro = currentColor, accento = var(--acc)
    marchio-piccolo-inline.svg  sorgente di #marchio-piccolo (sotto i 24 px)
    favicon.svg               si adatta al tema del sistema (prefers-color-scheme)
    favicon-png.svg           sorgente dei favicon PNG: marchio piccolo su quadrato scuro arrotondato
    icona-app.svg             sorgente di apple-touch-icon e android-chrome: fondo pieno, marchio al 57,5 %
    firma.svg                 la firma (marchio, ">tmuxify", cursore, motto) in testa a README.it.md;
                              testo in tracciati (JetBrains Mono 700, Manrope 500), geometria di .firma
    firma-chiaro.svg          per fondi chiari
    firma-en.svg              col motto in inglese, per README.md (e firma-en-chiaro.svg)

conf/icone/                   (ignorata da git, vedi conf/icone/LEGGIMI.md) — già generati:
  apple-touch-icon.png  android-chrome-192x192.png  android-chrome-512x512.png
  favicon-16x16.png  favicon-32x32.png  favicon.ico  favicon.svg  site.webmanifest
```

**Rigenerare** (dopo aver toccato `icone.json` o un SVG del marchio):

```bash
# non il python di sistema: l'env conda del progetto
conda create -n ttmux -c conda-forge python=3.12 cairosvg pillow   # una volta
conda run -n ttmux python design/esporta.py                         # icone + favicon
conda run -n ttmux python design/esporta.py --solo-icone            # solo icone (niente dipendenze)
```

---

## 3. Regole

### Marchio

- Sotto i 24 px si usa `marchio-piccolo*` (senza prompt). Sopra, `marchio*`.
- Intorno al marchio va lasciato libero almeno 1/4 del lato.
- Mai ricolorare i singoli pannelli, ruotarlo, aggiungere ombre, bagliori o sfumature.
- Il fondo pieno c'è solo nell'icona app e nei favicon PNG. Ovunque altrove il marchio sta su sfondo trasparente.
- Nella pagina il marchio arriva con lo sprite: `<svg class="marchio" aria-hidden="true"><use href="#marchio"></use></svg>` (o `#marchio-piccolo` sotto i 24 px). Il neutro prende il `color` del contenitore, l'accento `--acc`. La classe `.marchio` fissa solo le misure: niente `fill`/`stroke`, che sono già nei tracciati.

### Icone

- **Griglia 24**, area utile 20 (2 di margine), tratto **1,75 a 24 px, 1,9 a 20, 2 a 16**. Estremi e giunti tondi.
- **Colore sempre `currentColor`.** Le parti piene sono solo quelle disegnate piene (`f` in `icone.json`: barra-tmux, connesso, altro).
- Dimensioni ammesse: **16** (testata, barra del congelamento, aiuto), **20** (tasti del telefono), **24** (tavole, documentazione).
- Icona + testo dove c'è spazio. Icona sola **solo** con `aria-label` e `title` sul bottone; se c'è la scorciatoia, sta nel `title`. L'`<svg>` è sempre `aria-hidden="true"`.
- Un bottone che rappresenta uno stato acceso usa `.acceso` come oggi. Le icone che mostrano uno stato cambiano **disegno** (griglia-1/2/4/6, barra-tmux / barra-tmux-off, congela / riprendi), non colore.
- Un'icona nuova si aggiunge a `icone.json` con queste stesse regole, poi si rilancia `esporta.py`. Mai tracciati presi da altri set.

---

## 4. Il lavoro, in ordine

Un commit per passo. Riferimenti di riga su `conf/index.html.tmpl` attuale (possono slittare: fa fede il nome della funzione).

### Passo 1 — Sprite nella pagina, via Bootstrap Icons

1. **install.sh**: accanto a `@LICENZA@` (sed verso riga 448), aggiungere
   `-e "/@SPRITE@/r $RADICE/design/icone/sprite.svg" -e "/@SPRITE@/d"`.
   Se il file manca, l'installazione non deve rompersi: prima del sed, se
   `design/icone/sprite.svg` non c'è, usare un file vuoto in `$TMP` e scriverlo
   nel riepilogo finale.
2. **index.html.tmpl**: una riga `@SPRITE@` subito dopo `<body>` (riga 360), con un
   commento che dice da dove arriva e perché non è scritto nel modello.
3. Togliere il `<link>` a `bootstrap-icons` (righe 38–41 col suo commento). Bootstrap CSS e JS restano, servono ai tab.
4. CSS, al posto di `.bottone-gela .bi, .gelo-barra strong .bi { color: inherit; }` (riga 89):
   ```css
   .ico { width: 16px; height: 16px; flex: 0 0 auto; vertical-align: -3px;
          fill: none; stroke: currentColor; stroke-width: 2;
          stroke-linecap: round; stroke-linejoin: round; }
   .ico-20 { width: 20px; height: 20px; stroke-width: 1.9; }
   ```
5. `conIcona(elemento, nome, testo)` (riga 561): stesso contratto (ritorna lo span
   del testo), ma crea con `createElementNS` un
   `<svg class="ico" aria-hidden="true" focusable="false"><use href="#i-NOME"></use></svg>`.
   Lo span del testo prende la classe `testo` (serve al passo 2). Accanto,
   `impostaIcona(elemento, nome)`, che cambia l'`href` dell'`<use>` già presente
   invece di ricrearlo.
6. Sostituire i nomi (tutte le chiamate a `conIcona` e le voci `icona:` di `AIUTO`):

| prima | dopo | dove |
|---|---|---|
| `bi-box-seam` | `liberi` | bottoneScatola, aiuto |
| `bi-tag` | `nome-tab` | bottoneTitoli, aiuto |
| `bi-grid-3x3-gap` | `griglia-1` / `-2` / `-4` / `-6` | bottoneGriglia (secondo lo stato), aiuto (`griglia-4`) |
| `bi-keyboard` | `tasti` | bottoneTastiera, aiuto |
| `bi-clock-history` | `storia` | bottoneStoria, spia della storia, aiuto |
| `bi-layout-text-window-reverse` | `barra-tmux` / `barra-tmux-off` | bottoneBarra (secondo lo stato), aiuto |
| `bi-snow2` | `congela` (`riprendi` da congelato) | bottoneGela, titolo della barra del congelamento, aiuto |
| `bi-question-circle` | `aiuto` | bottoneAiuto |
| `bi-x-lg` | `chiudi` | ✕ del tab (`creaTab`, riga 745: oggi un `<i>`, diventa l'svg), aiuto |

**Fatto quando:** `grep -n "bi-\|bootstrap-icons" conf/index.html.tmpl` non trova niente e ogni bottone ha la sua icona.

### Passo 2 — Testata

1. **A›a / a›A** (`lettere()`, riga 634): sostituire le lettere con le icone `testo-meno` e `testo-piu`, senza testo. `etichetteFont()` mette già `title` e `aria-label` con la misura: resta così. Togliere il CSS `.lettera-g`, `.lettera-p`, `.verso`.
2. **Griglia** (`etichetteGriglia()`, riga 1881): `impostaIcona(bottoneGriglia, 'griglia-' + n)`, con n = `celleAdesso()`. Testo invariato: “Griglia” a 1, il numero sopra 1.
3. **Barra tmux** (`mostraBarraTmux()`, riga 607): `barra-tmux` se visibile, `barra-tmux-off` se nascosta. Testo invariato.
4. **Congela**: in `congela()` (riga ~1198, dove l'etichetta diventa “Riprendi”) l'icona diventa `riprendi`. In `scongela()` torna `congela`. In `avvisaCopia()` (riga ~1062), per la durata dell'avviso: `copiato` se è andata, `congela` se no (l'avviso “non riesco” resta testo rosso). Allo scadere, l'icona giusta per lo stato (congelato o no).
5. **Gruppi.** L'ordine in `barraDx` (riga ~705) è già quello giusto:
   `[liberi] | [testo-meno testo-piu] | [nome-tab griglia] | [tasti storia barra] | [congela aiuto]`.
   Aggiungere 4 `<span class="separatore" aria-hidden="true">` (1 × 18 px, `#363636`,
   margine orizzontale `.25rem`). Un separatore non resta mai doppio, né in testa
   o in coda, quando un bottone sparisce: oggi può sparire `bottoneScatola` (tutti
   aperti), `bottoneGriglia` (schermo stretto o un solo tab) e il gruppo intero
   se un domani ne spariscono altri. Si decide nel JS, nello stesso punto dove si
   nasconde il bottone, non con selettori CSS fragili.
6. **Testata compatta.** Con `body.schermo-medio` e `body.schermo-piccolo`, i bottoni
   mostrano solo l'icona: `.barra-dx .testo { display: none }` sotto quelle classi.
   Il nome resta in `aria-label` e `title`, con la scorciatoia dove c'è
   (Congela · Ctrl+Alt+C, Griglia · Ctrl+Alt+G, Nome dei tab · Ctrl+Alt+N, Aiuto · Ctrl+H).
   Eccezione: **il conto dei liberi resta visibile**, perché è un'informazione e
   non un'etichetta. `etichettaScatola` diventa due span, il numero (`.conto`,
   sempre visibile) e la parola “liberi” (`.testo`). Nessuna media query nel CSS:
   le soglie stanno solo in `SCHERMI`.
7. Bottone con sola icona: larghezza minima 28 px (32 sotto `schermo-piccolo`), icona centrata.

### Passo 3 — Tab: ✕ e spia di connessione

1. ✕ del tab: `chiudi` (vedi Passo 1).
2. **Spia di connessione** (nuova). In ogni tab, prima dell'etichetta, un
   `<svg class="ico ico-stato">` da **10 px**, con lo stato in `data-stato` sul
   bottone del tab: `connesso` | `riconnessione` | `scollegato`. L'icona segue lo
   stato (`connesso`, `riconnessione`, `scollegato`); il colore lo mette il CSS
   (`[data-stato=riconnessione] .ico-stato { color: #d4a24c }` e così via,
   `connesso` = `var(--acc)`). A 10 px usare `stroke-width: 3`.
   - **Da dove si prende lo stato:** `agganciaOverlay()` (riga 2633) vede già
     ogni avviso di ttyd. Nella sua `guarda(nodo)`, prima dei controlli su
     `CADUTA`, si aggiorna lo stato:
     `/reconnected/i` → `connesso`, `/to reconnect/i` → `scollegato`,
     `/connection closed|reconnecting/i` → `riconnessione`.
     All'aggancio (quando `.xterm` esiste) lo stato parte da `connesso`.
   - È **solo una spia**: non tocca la logica di chiusura (`controllaMorte`,
     `agganciaMorte`) né i nomi.
   - Accessibilità: il `title` del tab aggiunge lo stato quando non è `connesso`
     (“… · connessione caduta, si riconnette”, “… · scollegato: Invio nel
     terminale per riconnettere”).
   - I chip dei terminali liberi non hanno spia: non hanno websocket.

### Passo 4 — Barra del congelamento (`congela()`, riga 1125)

- Titolo: `conIcona(titolo, 'congela', 'Congelato')`.
- “Copia tutto”: icona `copia`. Se va a buon fine, per 1,4 s icona `copiato` e testo “Copiato”, poi torna com'era. Se non va, testo “Non riesco” con icona `copia`.
- “Riprendi (Esc)”: icona `riprendi`, testo “Riprendi · Esc”.
- La casella “ricongiungi le righe spezzate” diventa un **bottone interruttore**: `aria-pressed`, icona `a-capo`, testo “Unisci righe”, `.acceso` quando è attivo. Il comportamento (`schermata(term, …)`) non cambia.
- I bottoni della barra prendono lo stesso stile di `.bottone-gela`, sui toni blu della barra (bordo `#456578`, fondo `#1b2b38`), alti 26 px.

### Passo 5 — Tasti del telefono (`TASTI`, riga 2019)

- Aggiungere `icona` e `nome` a ogni voce:
  Esc → solo testo; Tab → icona `tab` + testo “Tab”;
  ← ↑ ↓ → → solo icona (`freccia-sx`, `freccia-su`, `freccia-giu`, `freccia-dx`), `aria-label` “Freccia a sinistra” ecc.;
  PagSu / PagGiu → solo icona (`pag-su`, `pag-giu`), `aria-label` “Pagina su” / “Pagina giù”.
  Icone in `.ico-20`.
- Nuovo ordine dell'array: **Esc, Tab, PagSu, PagGiu, ←, ↑, ↓, →**. L'ordine non conta per la logica e serve alle due righe qui sotto.
- Con `body.schermo-piccolo.mostra-tastiera` la barra passa a griglia `repeat(4, minmax(0, 1fr))`: prima riga Esc Tab PagSu PagGiu, seconda riga le frecce. Tasti alti **44 px**. Sopra `schermo-piccolo` resta una riga sola, come oggi.
- Spia della storia (riga 2057): icona `storia`.
- `pointerdown`, ripetizione e cattura del puntatore: invariati.

### Passo 6 — Aiuto

- Voci `icona:` rinominate (tabella del Passo 1). La voce “A›a  a›A” diventa `{ gesto: 'Testo più piccolo / più grande', icona: 'testo-meno', … }`.
- Nella testata della finestra, prima di “Scorciatoie”, il marchio a 18 px: `<use href="#marchio-piccolo">`, `color: #e8ebe9`.

### Passo 7 — Marchio nella pagina vuota

- Con `body.senza-tab` (nessun tab aperto, la fila dei liberi prende lo schermo), sopra la nota della scatola compare il marchio a 56 px: `<use href="#marchio">`, `color: #e8ebe9`, `aria-hidden="true"`. È l'unico posto “di benvenuto” della pagina.
- Fuori da `senza-tab` il marchio non c'è: la testata resta ai tab e ai bottoni.

### Passo 8 — Favicon e icona app

- I file sono già in `conf/icone/` (generati da `esporta.py`). `install.sh` li copia nel `WEBROOT`.
- **install.sh** (riga ~430): una riga in più per l'SVG:
  `icona favicon.svg "<link rel=\"icon\" type=\"image/svg+xml\" href=\"$PREFISSO/favicon.svg\">"`.
  Metterla dopo i PNG e verificare in Chrome e Firefox quale dei due usano.
  Tutti e due si leggono su schede chiare e scure: l'SVG perché cambia colore,
  i PNG perché hanno il quadrato scuro.
- `android-chrome-*.png` non hanno un `<link>`: li cita `site.webmanifest`, come già dice `LEGGIMI.md`.
- **conf/icone/LEGGIMI.md**: aggiungere `favicon.svg` alla tabella e una riga su `design/esporta.py`, che li rigenera.

### Passo 9 — Documentazione

- `README.it.md` e `README.md`: dire che le icone sono SVG in linea e non vengono più da CDN (la parte su Bootstrap da CDN, riga ~351, resta vera solo per Bootstrap); aggiungere `design/` all'albero dei file (riga ~589) e alla tabella “Aggiungere i favicon” (riga ~179).

---

## 5. Verifica

1. `grep -n "bi-\|bootstrap-icons" conf/index.html.tmpl` → niente.
2. `bash -n install.sh`.
3. **Resa senza server**: sostituire i segnaposto a mano in una copia temporanea
   (fuori dal repo), come fa `install.sh`: `@SPRITE@` col contenuto di
   `design/icone/sprite.svg`, `@TERMINALS@` con 4 terminali finti, `@TITOLO@`,
   `@PREFISSO@` vuoto, `@ICONE@` e `@LICENZA@` vuoti. Aprirla con Playwright
   (Chromium è già installato) a 1440, 800 e 390 px di larghezza e guardare gli
   screenshot. Gli iframe non caricano, ma la testata sì. Controllare:
   - nessun quadratino vuoto al posto di un'icona;
   - a 800 e 390 solo icone, con il conto dei liberi ancora visibile;
   - nessun separatore doppio o in testa quando griglia o liberi non ci sono;
   - a 390, con la barra dei tasti accesa: due righe da quattro, tasti da 44 px.
4. **Sul server** (`sudo ./install.sh --salta-pacchetti`, poi la dashboard):
   - `sudo systemctl restart ttyd@8701`: la spia di quel tab passa ambra e torna all'accento;
   - Ctrl+Alt+C: il bottone diventa “Riprendi” con l'icona play; Esc lo riporta a “Congela”;
   - la griglia cicla 1 → 2 → 4 e l'icona segue;
   - il favicon compare su scheda chiara e scura; “Aggiungi alla schermata Home” su iOS usa l'icona app.

---

## 6. Convenzioni del repo

- Commenti in italiano che spiegano il **perché**, come quelli che ci sono già. La sigla `[RR]` nei commenti e nei commit è di Roberto: non aggiungerla.
- Le soglie di schermo stanno **solo** nel JS (`SCHERMI`, `GRIGLIE`). Il CSS reagisce alle classi sul `body`.
- Mai spostare un `<iframe>` nel DOM: si ricarica, e si perdono websocket e scrollback.
- La pagina costruisce la UI via JS con `createElement`: continuare così, senza `innerHTML` con dentro dei dati.
- **Fine riga**: il working tree su Windows ha CRLF (e visto da Linux sembrano tutti modificati). Non normalizzare i file che non tocchi. I file nuovi di `design/` sono LF.
- Commit: uno per passo, formato `tipo(ambito): descrizione` in italiano, come nella storia (`feat(dashboard): …`, `feat(install): …`, `docs: …`). Commit e push solo quando Roberto lo chiede.

---

## 7. Fuori da questo lavoro

- **Menu “altro” sul telefono** (nella tavola, riquadro Telefono): rimandato alle regole UI/UX. L'icona `altro` è già nel set.
- Wordmark “tmuxify” (Manrope 800, spaziatura −0,045 em) e lockup orizzontale: non servono alla dashboard.
- Token completi (spazi, raggi, tipografia), stati hover/focus e accessibilità della tastiera: arrivano con le regole UI/UX.

## 8. Decisioni aperte (non bloccano)

- **Nome**: “tmuxify” (dalla bozza) contro `ttmux` (repo) e “Terminal Dashboard” (`TITOLO` di serie). Esiste già un progetto chiamato “tmuxifier”: verificare prima di adottarlo. Oggi il nome sta solo nel webmanifest (`esporta.py --nome`).

---

## Appendice — le 35 icone

| nome | etichetta | gruppo | sostituisce |
|---|---|---|---|
| liberi | Terminali liberi | testata | bi-box-seam |
| testo-meno | Testo più piccolo | testata | lettere A›a |
| testo-piu | Testo più grande | testata | lettere a›A |
| nome-tab | Nome dei tab | testata | bi-tag |
| griglia-1 / -2 / -4 / -6 | Griglia (mostra lo stato) | testata | bi-grid-3x3-gap |
| tasti | Tasti | testata | bi-keyboard |
| storia | Storia (copy-mode) | testata | bi-clock-history |
| barra-tmux / barra-tmux-off | Barra tmux visibile / nascosta | testata | bi-layout-text-window-reverse |
| congela | Congela | testata | bi-snow2 |
| aiuto | Aiuto | testata | bi-question-circle |
| altro | Altri comandi | testata | — (per il telefono, dopo) |
| chiudi | Chiudi il tab | tab | bi-x-lg |
| apri | Apri il terminale | tab | — (disponibile per i chip dei liberi) |
| trascina | Trascina | tab | — (disponibile) |
| terminale | Terminale | tab | — (disponibile) |
| copia / copiato | Copia tutto / Copiato | congelato | testo |
| riprendi | Riprendi | congelato | testo |
| a-capo | Unisci righe | congelato | casella |
| connesso / riconnessione / scollegato | Stato della sessione | stato | — (nuove) |
| tab | Tab | tasti | testo |
| freccia-sx / -su / -giu / -dx | Frecce | tasti | testo ← ↑ ↓ → |
| pag-su / pag-giu | Pagina su / giù | tasti | testo PagSu / PagGiu |
| certificato | Certificato | aiuto | — (disponibile) |
| licenza | Licenza | aiuto | — (disponibile, per “Leggi la licenza”) |
