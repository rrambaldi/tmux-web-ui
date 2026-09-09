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
| Aggiungere i favicon | i file in `conf/icone/`, poi `./install.sh --salta-pacchetti` |
| Controllare un'installazione in piedi | `sudo ./verifica.sh` — non modifica niente, e guarda anche il lato in chiaro |

## La dashboard

Un `index.html` che carica i terminali in `iframe`, uno per tab. Non e' un frontend
generico: sono tutte cose nate da un fastidio concreto.

- `Shift+←/→` cambia tab seguendo l'**ordine visivo**; `Alt+0–9` salta all'**id** del
  terminale, che non cambia mai anche se riordini.
- **Doppio click** sul tab per rinominarlo. I nomi stanno in `localStorage`: valgono
  per quel browser, non per il server.
- **Trascinamento** dei tab per riordinarli. Riordinare sposta il `<li>`, non ricrea
  l'iframe: la sessione e lo scrollback non si toccano.
- `Ctrl+Alt+C` (o il bottone **Congela**) ferma l'output del pannello e riversa la
  schermata in un `<pre>`: da li' selezione col mouse e `Ctrl+C` funzionano sempre.
  Serve perche' ttyd copia da solo a ogni cambio di selezione con
  `document.execCommand('copy')`, che il browser blocca in silenzio quando la
  selezione non nasce da un gesto utente breve — il famoso "a volte il copia-incolla
  non va". Congelare **non seleziona niente**: cosa copiare lo scegli tu. Se davvero
  serve tutta la schermata c'e' il bottone *Copia tutto*, e `Ctrl+Ins` copia la
  selezione di xterm senza nemmeno congelare.
- Quando la connessione cade, il **nome del tab torna al default**: se hai fatto `exit`
  la sessione tmux e' morta e al riaggancio `-A` ne crea una nuova, quindi l'etichetta
  descriverebbe qualcosa che non esiste piu'.
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
