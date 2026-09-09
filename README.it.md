# Terminali web: tmux + ttyd + nginx con mTLS

**N terminali persistenti raggiungibili dal browser**, ognuno una sessione `tmux` che
sopravvive alla chiusura della pagina, dietro un nginx che autentica **solo con
certificato client**.

*Documentation in English: [README.md](README.md).*

```
browser  --https + certificato client-->  nginx :443
             (mTLS: senza cert non entra)     |
                                              |  /            -> dashboard a tab (index.html)
                                              |  /term0/ ...  -> proxy_pass + websocket
                                              v
                                     ttyd :8700 ... :8709   (solo su 127.0.0.1)
                                              |
                                     tmux new-session -A -s term-87xx
                                              |
                                       bash -l  come utente non privilegiato
```

Tre pezzi, ognuno con un compito solo:

- **tmux** tiene in vita la sessione. Chiudi il browser, il lavoro continua.
- **ttyd** trasforma un TTY in websocket. Ascolta *solo* sulla loopback: non ha
  autenticazione propria e non deve essere raggiungibile da fuori.
- **nginx** fa TLS, mTLS e proxy. E' l'unica porta d'ingresso, ed e' l'unico posto
  dove si decide chi entra.

## Installazione

```bash
# 1. dire chi e dove
$EDITOR impostazioni.conf          # almeno DOMINIO e UTENTE

# 2. installare (root)
sudo ./install.sh

# 3. portare via il certificato e importarlo nel browser
scp root@SERVER:/root/certs-client/primo-accesso.p12 .
```

`install.sh` e' **idempotente**: lo si rilancia dopo aver modificato un modello in
`conf/` o `N_TERM`, e riallinea tutto (con backup dei file che sovrascrive).
`--salta-pacchetti` evita il giro di `dnf` nei rilanci.

Alla fine chiama `./verifica.sh`, che controlla le cose che contano davvero: che le
istanze siano attive, che **senza certificato non si entri** e che con il certificato
la dashboard e tutti i `/termN/` rispondano 200.

### Il primo accesso e' l'unico passaggio scomodo

Il servizio e' protetto dal certificato client, quindi **il certificato non puo'
essere scaricato dal servizio stesso**: va copiato via `scp` e importato a mano.

- **Chrome/Chromium/Edge** — Impostazioni > Privacy e sicurezza > Sicurezza >
  Gestisci certificati > *I tuoi certificati* > Importa.
- **Firefox** — Impostazioni > Privacy e sicurezza > Certificati > Mostra certificati
  > *Certificati personali* > Importa. Firefox ha un archivio suo, non quello di sistema.
- **iOS/macOS** — il `.p12` si apre come profilo; su iOS poi va *attivato* in
  Impostazioni > Generali > Info > Attendibilita' certificati.
- **Android** — Impostazioni > Sicurezza > Credenziali > Installa da memoria, scegliendo
  esplicitamente "certificato VPN e app".

Il `.p12` e' esportato in formato **legacy** (3DES/SHA1) di proposito: quello moderno
di OpenSSL 3 (AES-256 + PBKDF2) il keychain di iOS/macOS non lo importa. Il rovescio e'
che per riaprirlo da riga di comando serve la stessa opzione, o OpenSSL 3 si ferma su
`RC2-40-CBC: unsupported`:

```bash
openssl pkcs12 -info -nokeys -legacy -in /root/certs-client/primo-accesso.p12
```

### Aggiungere e togliere dispositivi

```bash
sudo certs/emetti-client.sh telefono-mario      # un certificato per dispositivo
sudo certs/emetti-client.sh portatile-mario 365 # durata in giorni
```

Un certificato per **dispositivo**, non per persona: il telefono perso si butta senza
toccare il resto. Per togliere l'accesso a uno solo serve una CRL — non c'e', e per
pochi dispositivi la strada pratica e' rigenerare la CA e riemettere i certificati.

## Adottare un'installazione esistente

I default di `impostazioni.conf` descrivono una macchina pulita. Su un server che una
cosa del genere ce l'ha gia', fatta a mano, non coincidono — e lanciare `install.sh`
con i default sbagliati e' peggio che non lanciarlo:

- `DOMINIO` vale `hostname -f`, cioe' il nome interno della macchina: non e' detto sia
  quello con cui la si raggiunge, ne' quello che sta nel certificato.
- `CA_CRT` punta a un file che non esiste. Questa e' quella che ti chiude fuori: nasce
  una CA **nuova**, nginx si fida solo di quella e tutti i certificati client gia'
  emessi smettono di funzionare. `crea-ca.sh` adesso si rifiuta di partire quando
  della CA trova un pezzo solo dove se l'aspetta — o ci sono entrambi e sono la stessa
  coppia, o non c'e' niente — ma puo' accorgersene solo se il file esistente sta
  proprio nel path configurato.
- `SSL_CRT` uguale: un certificato vero salvato con un altro nome non viene trovato, e
  al suo posto ne nasce uno autofirmato.
- `VHOST` vale `terminali.conf`, quindi un vhost esistente con un altro nome non viene
  sostituito ma *affiancato*: due server sulla 443, e nginx tiene il primo.

I valori veri vanno in `impostazioni.locale.conf`, che viene letto **prima** dei
default e non e' tracciato da git:

```bash
cat > impostazioni.locale.conf <<'EOF'
: "${DOMINIO:=term.esempio.it}"
: "${UTENTE:=mario}"
: "${SSL_CRT:=/etc/nginx/ssl/wildcard.esempio.it.crt}"
: "${SSL_KEY:=/etc/nginx/ssl/wildcard.esempio.it.key}"
: "${CA_CRT:=/etc/ssl/certs/come-si-chiama-la-CA-esistente.crt}"
: "${CA_KEY:=/etc/ssl/private/come-si-chiama-la-CA-esistente.key}"
: "${VHOST:=/etc/nginx/conf.d/www.conf}"
EOF
```

La forma `: "${VAR:=valore}"` va mantenuta: la precedenza e' **ambiente >
`impostazioni.locale.conf` > `impostazioni.conf`**, e i valori derivati (`SSL_CRT` dal
`DOMINIO`, e cosi' via) si calcolano dopo la lettura del file locale, quindi seguono i
valori veri e non i default.

Poi si guarda prima di saltare: `./verifica.sh` non modifica niente e dice com'e' la
situazione adesso, e `install.sh` stampa il riepilogo completo prima di toccare
qualsiasi cosa.

## Manutenzione

| Cosa | Come |
|---|---|
| Cambiare numero di terminali | `N_TERM` in `impostazioni.conf`, poi `./install.sh --salta-pacchetti` |
| CA scaduta | `sudo certs/rinnova-ca.sh` — rifirma con la **stessa** chiave e lo stesso DN, i certificati client restano validi |
| Certificato server scaduto | rigenerarlo con `certs/cert-server.sh`, o puntare `SSL_CRT`/`SSL_KEY` a un certificato vero |
| Vedere cosa gira | `systemctl status 'ttyd@*'`, `runuser -u UTENTE -- tmux ls` |
| Ridurre `N_TERM` | le unit in eccesso restano attive: `systemctl disable --now ttyd@8709` a mano |
| Passare da mTLS stretto a diagnostico | `VERIFICA_CLIENT` (`on` / `optional`), poi `./install.sh --salta-pacchetti` |
| Chiudere anche la porta 80 | `PROTEGGI_80` (`nome` / `default` / `no`), poi `./install.sh --salta-pacchetti` |
| Nomi dei tab legati all'utente | `PROFILI` (`si` / `no`), poi `./install.sh --salta-pacchetti` |
| Azzerare il profilo di qualcuno | `rm $DIR_PROFILI/<cn>.json` — al prossimo accesso si ricrea |
| Aggiungere i favicon | i file in `conf/icone/`, poi `./install.sh --salta-pacchetti` |
| Controllare un'installazione in piedi | `sudo ./verifica.sh` — non modifica niente, e guarda anche il lato in chiaro |

## La dashboard

Un `index.html` che carica i terminali in `iframe`, uno per tab. Non e' un frontend
generico: sono tutte cose nate da un fastidio concreto.

- `Shift+←/→` cambia tab seguendo l'**ordine visivo**; `Alt+0–9` salta all'**id** del
  terminale, che non cambia mai anche se riordini.
- `Ctrl+H` (o il bottone **`? Aiuto`**) apre l'**elenco delle scorciatoie**: tasti, gesti
  col mouse e cosa fa ogni bottone della testata. Prima era un rigo di testo in testata,
  che spariva sotto i 1100px — cioe' era leggibile solo dove c'era spazio per fare a meno
  di leggerlo. Si chiude con `Esc`, col bottone o cliccando fuori dalla carta; finche' e'
  aperta i tasti restano li' e non finiscono nel terminale dietro. **Nota**: nel terminale
  `Ctrl+H` e' `^H`, cioe' backspace per readline e per `vi` in inserimento — e' l'unica
  scorciatoia della pagina che non passa da `Ctrl+Alt`, e se da fastidio cambiarla e' una
  riga sola.
- `Ctrl+F2` rinomina il terminale attivo (in griglia: quello della cella attiva), o
  **doppio click** sul tab. Con i profili accesi (`PROFILI`) i nomi e
  l'ordine seguono **l'identita' del certificato**, non il browser: li ritrovi cambiando
  browser o riaprendo in incognito. `localStorage` resta come cache, quindi la pagina
  non aspetta la rete e funziona anche se il server non risponde.
- **Trascinamento** dei tab per riordinarli. Riordinare sposta il `<li>`, non ricrea
  l'iframe: la sessione e lo scrollback non si toccano.
- **Griglia**: il bottone `⊞ Griglia` in testata (o `Ctrl+Alt+G`) mostra **2, 4 o 6
  terminali insieme** e cicla fra i formati che lo schermo regge — 2 affiancati, 4 in
  2×2, 6 in 3×2. Compare solo dove c'e' spazio davvero (2 da 1200px, 4 da 1500×800, 6
  da 1900×800): sotto i ~600px per cella un terminale non tiene 80 colonne a un font
  leggibile, e sei finestrelle illeggibili valgono meno di una sola che si legge; su un
  telefono il bottone non c'e' proprio. La griglia e' un **insieme** di terminali, non
  un'assegnazione cella per cella: l'ordine in cui compaiono e' quello dei tab, percio'
  le celle si spostano trascinando i tab come sempre, senza imparare un secondo modo di
  riordinare. Da qui una regola sola, valida per il click su un tab, per `Alt+0–9` e per
  `Shift+←/→`: **se quel terminale e' gia' a schermo la sua cella diventa quella attiva,
  se non c'e' prende il posto della cella attiva**. La cella attiva ha la cornice verde
  ed e' quella che riceve i tasti, `Congela`, `Storia` e la barra dei tasti; si sceglie
  anche cliccando dentro il terminale. Lo stesso terminale non puo' stare in due celle,
  e non e' una scelta di gusto: sarebbero due client sulla stessa sessione tmux, e tmux
  dimensiona la finestra sul client piu' piccolo. Formato e insieme stanno nel profilo,
  quindi si ritrovano cambiando browser; se lo schermo non regge il formato scelto si
  stringe al piu' grande che ci sta **senza dimenticare la preferenza**, cosi' il
  telefono non cancella la griglia del portatile. Le celle non spostano nessun iframe
  nel DOM — lo ricaricherebbe, perdendo lo scrollback — si accendono con `display` e si
  mettono in fila con `order`.
- `Ctrl+Alt+C` (o il bottone **Congela**) ferma l'output del pannello e riversa la
  schermata in un `<pre>`: da li' selezione col mouse e `Ctrl+C` funzionano sempre.
  Serve perche' ttyd copia da solo a ogni cambio di selezione con
  `document.execCommand('copy')`, che il browser blocca in silenzio quando la
  selezione non nasce da un gesto utente breve — il famoso "a volte il copia-incolla
  non va". Congelare **non seleziona niente**: cosa copiare lo scegli tu. Se davvero
  serve tutta la schermata c'e' il bottone *Copia tutto*, e `Ctrl+Ins` copia la
  selezione di xterm senza nemmeno congelare.
- Una **barra di tasti** in fondo alla pagina per `Esc`, `Tab`, le quattro frecce e
  `PagSu`/`PagGiu`: la tastiera di sistema di un telefono non li ha, e senza di quelli
  in `tmux` o in `vi` non ci si muove e non si completa un nome di file. Tenendo premuto
  si ripetono, come farebbe un tasto vero. Compare da se' dove il puntatore e' un dito
  (`pointer: coarse`) e si accende o si spegne col bottone **`⌨ Tasti`** in testata, con
  la scelta ricordata in `localStorage`. Col pannello congelato i tasti si spengono:
  passano da `term.input()`, che rispetta `disableStdin` come la tastiera vera.
- **Modalita' storia**: il bottone `⇱ Storia` in testata entra e esce dalla copy-mode di
  `tmux` (quella di `Ctrl-B [`), dove le frecce e `PagSu`/`PagGiu` scorrono lo
  scrollback invece di andare al programma. Il bottone sta in testata e non nel footer
  cosi' c'e' anche sul desktop, e si accende quando la modalita' e' attiva; nel footer
  compare la spia `⇱ storia · le frecce scorrono`, che e' dove guardi mentre premi le
  frecce. Lo stato **non** e' il conto dei nostri click: si legge da cio' che tmux
  disegna, quindi la spia e' giusta anche se entri o esci con la tastiera vera.
- **`A›a` / `a›A`** cambiano la dimensione dei caratteri del terminale: il verso lo
  disegna la dimensione stessa delle due lettere, che non c'e' bisogno di tradurre. La scelta batte
  l'adattamento automatico e resta in `localStorage`; tornando esattamente sul valore
  che l'automatico avrebbe scelto la scelta si butta, e si ricomincia ad adattarsi allo
  schermo senza bisogno di un terzo bottone "auto". Sta in `localStorage` e **non** nel
  profilo sul server, di proposito: la dimensione giusta dipende dallo schermo che hai
  davanti, e un valore condiviso fra telefono e portatile sarebbe sbagliato su almeno
  uno dei due.
- La pagina **si adatta allo schermo**. Su un telefono i tab di Bootstrap a misura da
  desktop occupano tre righe (~150px su 700) che vengono tolte al terminale: sotto i
  480px si stringono e le etichette lunghe si troncano, sotto i 900px un po' meno. Nello
  stesso passaggio cala il font del terminale (11px sotto 480, 12px sotto 900, altrimenti
  quello di ttyd), perche' e' il font a decidere quante colonne ci stanno: su un telefono
  da 390px si passa da una cinquantina a una sessantina, e in `htop` o in un `diff` si
  vede. I limiti stanno in un solo posto, `SCHERMI` nel JS: il CSS non ha media query
  sue, reagisce alle classi che il JS mette sul `body`. In griglia la larghezza che conta
  non e' quella della finestra ma quella della **cella**: un 1920 diviso in tre da' celle
  da 630, e li' il font e' quello che si userebbe su uno schermo da 630.
- Quando la connessione cade, il **nome del tab torna al default**: se hai fatto `exit`
  la sessione tmux e' morta e al riaggancio `-A` ne crea una nuova, quindi l'etichetta
  descriverebbe qualcosa che non esiste piu'. Con tre eccezioni, perche' qui si cancella
  una cosa scritta a mano: **non** si azzera niente mentre la pagina se ne va
  (`pagehide`/`beforeunload`), mentre non e' a schermo, e per qualche secondo dopo che ci
  e' tornata. Ricaricando, le websocket cadono per forza e ttyd fa in tempo a scrivere
  "Connection Closed": senza quelle guardie il nome veniva azzerato proprio durante l'F5 —
  ed e' il difetto che faceva sembrare che i nomi non si salvassero. Al ritorno da un
  telefono bloccato vale lo stesso: quella e' la coda della disconnessione di sistema,
  non un `exit`. L'azzeramento inoltre **non aggiorna la data** del profilo: non e' una
  modifica voluta, e non deve vincere su quello che c'e' sul server.
- I messaggi di ttyd ("Reconnecting…", "Press ⏎ to Reconnect") sono forzati a
  **sans-serif** via `MutationObserver`: sono un `<div>` che ttyd appende dentro
  l'iframe con lo stile tutto in linea, quindi ne' il CSS della pagina ne' una regola
  senza `!important` li raggiungerebbero.

Bootstrap arriva da CDN: **serve internet sul client** (non sul server). Per un
ambiente chiuso, scaricare i due file nel webroot e correggere i due URL in
`conf/index.html.tmpl`.

## Trappole, tutte verificate sul campo

**Le due modalita' dell'mTLS.** `VERIFICA_CLIENT` in `impostazioni.conf` decide chi
respinge chi non ha il certificato, e il default e' la stretta:

- **`on`** (default) — lo pretende nginx durante l'handshake TLS: senza certificato la
  richiesta muore con `400 No required SSL certificate was sent` e non arriva a
  nessuna `location`.
- **`optional`** — la connessione entra e la respinge il vhost con
  `if ($ssl_client_verify != SUCCESS) { return 403; }`, rispondendo *quale* dei tre
  casi e' (assente, scaduto, CA sbagliata) invece del 400 secco che non dice niente
  proprio mentre sei chiuso fuori dal tuo server.

Il prezzo di `optional` e' che **la protezione diventa quel controllo**: se lo togli,
tutte le shell (scrivibili, con sudo se l'utente ce l'ha) restano raggiungibili da
chiunque arrivi sulla 443 senza dover dimostrare niente. E' successo davvero, per mezza
giornata. Il controllo viene generato in entrambe le modalita': con `on` non scatta mai,
e sta li' perche' passare a `optional` sia una variabile e non una revisione di
sicurezza.

**I profili non hanno bisogno di un backend.** Nomi e ordine dei tab stanno in un JSON
per identita', e a servirlo e a scriverlo e' nginx stesso: il pacchetto di Rocky ha
`ngx_http_dav_module` compilato, quindi il `PUT` lo accetta da se'. Niente processi in
piu' da tenere in piedi, niente porte nuove, tutto dentro l'mTLS che c'e' gia'.

L'identita' e' il **CN del certificato client**, l'unica cosa che il servizio sa di chi
entra. nginx non ha una variabile per il CN, solo il DN intero: si estrae con una `map`,
e attenzione al formato — `$ssl_client_s_dn` e' in RFC2253, che stampa il DN *al
contrario*, e se il certificato ha un `emailAddress` quello viene **prima** del CN. La
regex lo cerca quindi in mezzo alla stringa e non in testa.

Il file deve chiamarsi esattamente come l'identita', e a garantirlo e' un backreference
in una seconda `map`:

```nginx
map "$cn_client:$uri" $profilo_mio {
    default                                   0;
    "~^([A-Za-z0-9._-]+):/profili/\1\.json$"  1;
}
```

Cosi' non serve fidarsi del percorso che arriva dal browser: chiedere il profilo di un
altro da' 403, e lo da' anche scriverlo. Un CN assente, vuoto, troppo lungo o con
caratteri che non stanno in un nome di file diventa identita' vuota, e senza identita'
non si legge e non si scrive niente.

Due conseguenze da tenere a mente:

- **Un certificato per dispositivo vuol dire un profilo per dispositivo.** Due browser
  che importano lo stesso `.p12` condividono i nomi; telefono e portatile con
  certificati distinti restano separati. E' la stessa separazione che serve per
  revocare un dispositivo solo.
- **Vince l'ultimo che scrive, non l'ultimo che carica.** Con due browser aperti insieme
  non c'e' fusione: chi rinomina per ultimo sovrascrive, e per dei nomi di tab e' un
  prezzo accettabile. Ma "ultimo" e' deciso da una data, non dall'ordine in cui le pagine
  si aprono: ogni modifica locale lascia un timestamp in `localStorage` e la `PUT` se lo
  porta dietro nel campo `agg`. Quando la pagina si carica, se la data locale e' piu'
  recente di quella del profilo e' **la cache ad avere ragione**, e a salire; altrimenti
  vince il profilo. Senza questo bastava ricaricare entro gli 800ms del debounce — o
  avere una `PUT` rifiutata, o essere senza rete — per veder tornare i nomi di prima: la
  rinomina era in `localStorage`, ma il caricamento successivo la sovrascriveva con la
  copia vecchia del server. Sono orologi di macchine diverse, quindi fra telefono e
  portatile sfasati vince chi ha l'orologio avanti; ma il caso che conta — ho cambiato
  qui e ricarico qui — e' lo stesso browser, dove le date sono ordinate per forza.
  In piu' la `PUT` in attesa parte subito su `pagehide` e quando la pagina passa in
  secondo piano (con `keepalive`, o il browser l'annullerebbe), cosi' la finestra in cui
  qualcosa puo' non essere ancora salito si chiude quasi sempre da se'.

Una cosa che si sceglie di *non* propagare: quando la connessione cade, l'etichetta
torna al default (vedi sotto), ma quel ritorno resta **locale**. Se salisse al server,
una websocket caduta — un riavvio di nginx, il telefono che perde campo — cancellerebbe
il nome su tutti i browser di quella identita'. Al server salgono solo le rinomine
volute.

**La porta 80 non e' tua.** L'mTLS difende la 443 e non dice niente sulla 80, dove la
configurazione di serie di nginx tiene

```nginx
server { listen 80; server_name _; root /usr/share/nginx/html; }
```

che serve **lo stesso webroot della dashboard**, in chiaro e senza chiedere niente a
nessuno. I terminali non ci sono (`/term0/` e compagnia rispondono 404 su quella porta,
esistono solo nel vhost con mTLS): quello che esce e' la pagina della dashboard e,
molto peggio, *qualunque file lasciato nel webroot*. `PROTEGGI_80` decide quanto in
largo tirare la coperta:

| valore | cosa installa | copre |
|---|---|---|
| `nome` (default) | un server sulla 80 per il solo `$DOMINIO`, `301` verso https | `http://tuo.host/…` |
| `default` | il precedente, piu' `listen 80 default_server` che risponde `444` | anche l'IP nudo e gli `Host:` sconosciuti |
| `no` | niente | niente |

Su una macchina dedicata la risposta giusta e' `default`. Non e' il default perche' e'
l'unico pezzo di questa installazione che cambia il comportamento della macchina
*fuori* dai terminali: su un server condiviso spegnerebbe gli altri siti http che non
hanno un `server_name` proprio.

Nessuna delle tre e' comunque *la* protezione. La protezione e' che **nel webroot non
ci stia mai materiale crittografico**, e `install.sh` si rifiuta di partire se ne
trova.

**SELinux.** Con SELinux **enforcing** nginx non puo' aprire connessioni verso ttyd:
`proxy_pass` fallisce con 502 e in `audit.log` compare `name_connect`. `install.sh`
mette `httpd_can_network_connect=1`. Sul server originale il problema non si vedeva
perche' e' in *Permissive* — replicandolo su una macchina enforcing sarebbe stato il
primo intoppo.

**ttyd e' read-only per default** dalla 1.7.0: senza `-W` il terminale si vede ma non
si scrive. E' nella unit.

**`tmux new-session -A`** riattacca se la sessione esiste, altrimenti la crea. E' cio'
che rende il terminale persistente. Il rovescio: con `exit` la sessione muore per
sempre e al riaggancio ne trovi una nuova e vuota.

**`KillMode=process` nella unit, e non e' un dettaglio di stile.** Il server tmux non
nasce come processo a se': lo avvia il *primo* `tmux new-session` che parte, quindi
finisce nel cgroup di quella unit `ttyd@`. Col `KillMode` di default
(`control-group`), fermare quella unit uccide tutto il suo cgroup — server tmux
compreso — e con esso **tutte** le sessioni, non solo la sua. `install.sh`, che fa
`restart` su ogni porta, azzerava quindi il lavoro aperto in tutti i terminali, mentre
questo file ha sempre affermato il contrario.

Su una macchina viva si e' visto cosi': dieci sessioni, un solo server tmux, e il suo
processo nel cgroup di `ttyd@8708` — insieme a shell di lavoro, sessioni `ssh` e un
processo di test. Un `systemctl restart ttyd@8708` le avrebbe portate via tutte.

Con `KillMode=process` si ferma solo `ttyd`: client e server tmux restano, e al
riaggancio `-A` ritrova la sessione. **Se stai aggiornando un'installazione nata prima
di questa riga**, il primo `install.sh` e' ancora quello che azzera tutto: installa la
unit nuova e fai solo `systemctl daemon-reload`, senza `restart`, lasciando che la
`KillMode` nuova valga dal riavvio successivo.

**Non mettere il `.p12` nel webroot.** Sembra comodo per importarlo dal telefono, ma
e' la chiave di casa lasciata sotto lo zerbino — e lo zerbino sta sulla strada: il
webroot lo serve anche il server sulla 80 della configurazione di serie di nginx, in
chiaro e senza chiedere alcun certificato. Un `.p12` la' dentro e' l'unica
autenticazione del servizio pubblicata su internet, protetta da una passphrase che
chi lo scarica puo' macinare offline con tutta calma. Gli script lo scrivono in
`/root/certs-client` a `0600` di proposito, `install.sh` si rifiuta di partire se nel
webroot trova un `.p12`, `.key`, `.pem`, `.crt` o `.csr`, e `verifica.sh` controlla la
stessa cosa stampando l'URL in http da cui il file si scarica — che di solito chiude
la discussione.

**Le icone si generano da quello che c'e'.** I `<link>` dentro `index.html` vengono
emessi uno per ogni file davvero presente nel webroot (o in `conf/icone/`, da cui
`install.sh` li copia). Un `<link>` verso un'icona che non c'e' e' un 404 a ogni
caricamento, e un elenco fisso e' un elenco che invecchia: i binari non stanno nel
repo, ma un server che le ha gia' si tiene le sue icone anche dopo un rilancio.

**Timeout della websocket.** Il vhost mette `proxy_read_timeout 1d`: col default di 60s
una sessione lasciata ferma verrebbe chiusa da nginx e il terminale andrebbe in
reconnect. Sull'originale non si notava perche' la status line di tmux si aggiorna ogni
15s e tiene il canale caldo — cioe' funzionava per un effetto collaterale.

**Come si sa se la copy-mode e' attiva.** Non tenendo il conto dei click sul bottone:
con una tastiera vera si entra e si esce da soli, e una spia che mente e' peggio di
nessuna spia. Si guarda invece cio' che **tmux disegna**: in copy-mode scrive
l'indicatore di posizione `[riga/totale]` in alto a destra del pannello, e quel disegno
finisce nel buffer di xterm.js. Verificato registrando il pty di un client tmux vero:
entrando in copy-mode compare `[0/179]`.

Attenzione, perche' `capture-pane` **non** lo mostra: quello cattura il contenuto del
pannello, mentre l'indicatore lo disegna il client. Per vederlo serve registrare il pty
di un client attaccato (`script -f ... -c "tmux attach -t ..."`).

Il solo `[n/m]` in fondo alla riga non basta: una barra di avanzamento che stampa
`[1/10]` accenderebbe la spia. L'indicatore di tmux e' disegnato con `mode-style`, che
di serie e' `bg=yellow`, quindi si chiede anche allo **sfondo** delle celle: su testo
normale e' quello di default.

Per uscire si manda **Esc** e non `q`: Esc annulla la copy-mode in entrambe le tabelle
di tmux (`copy-mode` ed `copy-mode-vi`) e, se lo stato rilevato fosse sbagliato, fuori
dalla copy-mode non fa danni — mentre `q` scriverebbe una lettera nella shell.

**Le frecce hanno due forme.** Col modo cursore "applicazione" attivo (DECCKM, lo
accendono `vi` e in genere le interfacce a tutto schermo) una freccia e' `ESC O A`, negli
altri casi `ESC [ A`. La barra dei tasti guarda `term.modes.applicationCursorKeysMode`
prima di decidere: mandare sempre la seconda forma funziona nella shell e si rompe
altrove. `Esc` e' `ESC`, `Tab` e' `HT` (0x09), `PagSu`/`PagGiu` sono `ESC [ 5~` e
`ESC [ 6~` — sono le stesse sequenze che xterm.js emette per quei tasti.

**Copia-incolla:** la soluzione vera sarebbe una versione di ttyd che includa
`@xterm/addon-clipboard`, cioe' OSC 52, piu' `tmux set -g set-clipboard on`. Nel
bundle della **1.7.7 di EPEL** xterm.js registra gli handler OSC 0, 1, 2, 4, 8,
10-12, 104, 110-112 e 1337: il **52 non c'e'**, quindi la sequenza non verrebbe
consumata da nessuno e non serve nemmeno provare. Per questo qui si aggira con il
congelamento (`Ctrl+Alt+C`).

## Inventario

```
impostazioni.conf              tutte le variabili, un posto solo
impostazioni.locale.conf       opzionale, non tracciato: i valori veri di QUESTO server
install.sh                     installatore idempotente end-to-end
verifica.sh                    controlla che la replica funzioni davvero
conf/ttyd@.service.tmpl        unit template: una istanza per porta
conf/nginx-terminali.conf.tmpl vhost: TLS, mTLS, websocket, proxy dei /termN/
conf/nginx-80.conf.tmpl        porta 80: redirect a https (vedi PROTEGGI_80)
conf/nginx-80-default.inc      blocco in piu' per PROTEGGI_80=default: prende il default server
conf/nginx-profili-map.inc     le map che ricavano l'identita' dal certificato
conf/nginx-profili.inc         /io e /profili/: il profilo per utente, servito da nginx
conf/index.html.tmpl           la dashboard a tab
conf/icone/                    favicon opzionali, copiati nel webroot e linkati se presenti
certs/comune.inc               estensioni x509 e controlli condivisi
certs/crea-ca.sh               crea la CA client (l'autenticazione del servizio)
certs/cert-server.sh           certificato TLS del server (autofirmato o CSR)
certs/emetti-client.sh         emette un .p12 + PEM per un dispositivo
certs/rinnova-ca.sh            rifirma la CA senza invalidare i client
```

## Differenze rispetto all'installazione da cui nasce

Il comportamento e' lo stesso, la forma no:

- **Una sola unit** invece di `ttyd@.service` + un drop-in per l'utente: nell'originale
  il drop-in e' storia (l'unit era nata con `User=root`), qui non serve.
- **CA e certificato server con nomi propri** (`terminali-ca.*`): l'originale riusa la
  CA aziendale e un certificato wildcard gia' esistenti. Puntando `CA_*` e `SSL_*` a
  quei file si ottiene la stessa cosa.
- **`proxy_read_timeout 1d` aggiunto** (vedi sopra).
- **Icone opzionali**: nell'originale i `<link>` dei favicon sono scritti a mano nella
  pagina. Qui li genera `install.sh` in base ai file presenti, cosi' un rilancio non
  li perde e un host senza icone non si ritrova quattro 404 per pagina.
- **La porta 80 gestita** (`PROTEGGI_80`): nell'originale era rimasta quella di serie,
  e serviva il webroot in chiaro.

## Requisiti

Rocky/RHEL/Alma 9 con EPEL (`ttyd` sta li'), `nginx`, `tmux`, `openssl`. Su
Debian/Ubuntu il grosso vale identico, cambiano tre cose: `apt install ttyd tmux nginx`,
il vhost va in `/etc/nginx/sites-available` con symlink in `sites-enabled`, e SELinux
non c'e' (c'e' AppArmor, che di norma non ostacola questo caso).

## Licenza

MIT — vedi [LICENSE](LICENSE).
