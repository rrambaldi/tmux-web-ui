<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/marchio/firma.svg">
    <img src="design/marchio/firma-chiaro.svg" alt="tmuxify — Terminale persistente. Sessioni connesse." width="426">
  </picture>
</p>

# Terminali web: tmux + ttyd + nginx con mTLS

Terminali nel browser che non muoiono quando chiudi la pagina. Ognuno e' una sessione
`tmux`. Si entra solo con un **certificato client**.

Sono shell vere su una porta pubblica: leggi le [trappole](#trappole-tutte-verificate-sul-campo)
prima di metterlo in rete.

*Documentation in English: [README.md](README.md).*

![Architettura: browser, nginx con mTLS, ttyd, tmux, bash](design/architecture.png)

*Schema per gentile concessione di ChatGPT.*

Tre pezzi, un compito ciascuno:

- **tmux** tiene viva la sessione. Chiudi il browser, il lavoro continua.
- **ttyd** trasforma il terminale in una websocket. Ascolta solo su `127.0.0.1`: non ha
  password, e da fuori non deve arrivarci nessuno.
- **nginx** fa TLS, mTLS e proxy. E' l'unica porta d'ingresso: decide lui chi entra.

## Requisiti

- Rocky/RHEL/Alma 9 con EPEL (`ttyd` sta li'), oppure Fedora, dove `ttyd` sta nei repo
  base e EPEL non serve. Provato su Rocky Linux 9 e Fedora 39.
- `ttyd`, `tmux`, `nginx`, `openssl`: li installa `install.sh` con `dnf`.
- Debian/Ubuntu: vale quasi tutto. Cambiano tre cose: `apt install ttyd tmux nginx`, il
  vhost va in `/etc/nginx/sites-available` con un symlink in `sites-enabled`, e SELinux non
  c'e' (AppArmor di solito non da' fastidio).
- Il **browser** deve avere internet, perche' Bootstrap arriva da CDN. Il server no. Per una
  rete chiusa: scarica i due file nel webroot e cambia i due URL in `conf/index.html.tmpl`.

## Installazione

```bash
# 1. dire chi e dove
$EDITOR impostazioni.conf          # almeno DOMINIO e UTENTE

# 2. installare (root)
sudo ./install.sh

# 3. portare via il certificato e importarlo nel browser
scp root@SERVER:/root/certs-client/primo-accesso.p12 .
```

Al primo lancio, da terminale, `install.sh` fa qualche domanda:

1. **Il nome del sito.** Se nginx lo serve gia' sulla 443, i terminali vanno sotto un suo
   path (default `/term`) e ti propone di usare la CA client del sito. Se no, hanno un URL
   tutto loro.
2. **Quanti terminali, e con quale utente** girano le shell. Se l'utente non c'e', lo crea.
3. **Il certificato del server**, se `SSL_CRT` non esiste ancora. Cerca quelli validi per
   `DOMINIO` (quelli che usa nginx e `/etc/letsencrypt/live/*`) e chiede quale usare.
   `--force` salta la ricerca e crea un autofirmato.

Una risposta sbagliata si richiede: lo script non si ferma. Le risposte finiscono in
`impostazioni.locale.conf` e non si richiedono piu'. Per rifarle, cancella quel file. Senza
terminale valgono i default.

Alla fine parte `./verifica.sh`. Controlla che i terminali girino, che **senza certificato
non si entri**, e che col certificato la dashboard e ogni `/termN/` rispondano 200.

Puoi rilanciare `install.sh` quando vuoi: riallinea tutto e salva una copia di quello che
sovrascrive. `--salta-pacchetti` salta `dnf`.

Il numero dei terminali sta in un posto solo: `N_TERM`. Tab, `upstream` e `location` di
nginx e unit systemd si generano da li'.

### Primo accesso: importare il certificato

Il certificato non si scarica dal servizio: senza certificato non entri. Copialo con `scp` e
importalo a mano.

- **Chrome/Chromium/Edge** — Impostazioni > Privacy e sicurezza > Sicurezza >
  Gestisci certificati > *I tuoi certificati* > Importa.
- **Firefox** — Impostazioni > Privacy e sicurezza > Certificati >
  Mostra certificati > *Certificati personali* > Importa. Firefox ha un archivio suo, non usa quello di sistema.
- **iOS/macOS** — il `.p12` si apre come profilo. Su iOS poi va *attivato* in
  Impostazioni > Generali > Info > Attendibilita' certificati.
- **Android** — Impostazioni > Sicurezza > Credenziali > Installa da memoria, e scegli
  "certificato VPN e app".

Il `.p12` e' in formato **legacy** (3DES/SHA1) apposta: quello nuovo di OpenSSL 3
(AES-256 + PBKDF2) il portachiavi di iOS/macOS non lo prende. Per leggerlo da riga di comando
serve `-legacy`, se no OpenSSL 3 si ferma con `RC2-40-CBC: unsupported`:

```bash
openssl pkcs12 -info -nokeys -legacy -in /root/certs-client/primo-accesso.p12
```

### Aggiungere dispositivi

```bash
sudo certs/emetti-client.sh telefono-mario      # un certificato per dispositivo
sudo certs/emetti-client.sh portatile-mario 365 # durata in giorni
```

Un certificato per **dispositivo**, non per persona: se perdi il telefono butti solo quello.
Per revocarne uno servirebbe una CRL, e non c'e'. Con pochi dispositivi si fa prima: nuova CA
e nuovi certificati.

### Sotto un path di un sito esistente

Con `PREFISSO=/term` non nasce un `server{}` nuovo. Il servizio sta in
`https://DOMINIO/term/`, dentro il `server{}` https del sito, col suo certificato e la sua CA
client.

```bash
# impostazioni.locale.conf
: "${DOMINIO:=www.esempio.it}"
: "${PREFISSO:=/term}"
: "${CA_CRT:=/etc/pki/esempio-ca/ca.crt}"   # la ssl_client_certificate del sito
: "${CA_KEY:=/etc/pki/esempio-ca/ca.key}"
```

- `install.sh` cerca il file del sito in `/etc/nginx/conf.d` (`server_name DOMINIO` + 443).
  Si ferma se manca `ssl_verify_client optional|on`, o se la CA del sito non e' `CA_CRT`.
- Le location vanno in `INCLUDE_PATH` (`/etc/nginx/terminali-path.inc`), upstream e map in
  `VHOST`.
- La riga `include` nel `server{}` del sito la aggiunge dopo averti chiesto, con una copia
  di backup. Se `nginx -t` fallisce, la toglie.
- Ogni location controlla da sola `$ssl_client_verify`: il resto del sito puo' restare
  pubblico.
- La dashboard va in `/usr/share/nginx/terminali`, non nella root del sito.
- La porta 80 resta al sito.

### Adottare un'installazione esistente

I default di `impostazioni.conf` pensano a una macchina pulita. Su un server che ha gia'
un'installazione fatta a mano non tornano, e lanciare `install.sh` coi default sbagliati fa
danni:

- `DOMINIO` vale `hostname -f`: il nome interno della macchina, non per forza quello con cui
  ci si arriva o quello nel certificato.
- `CA_CRT` punta a un file che non c'e'. **Questa ti chiude fuori**: nasce una CA nuova,
  nginx si fida solo di lei, e i certificati client gia' dati smettono di andare.
  `crea-ca.sh` si ferma se della CA trova solo meta', ma se ne accorge solo se il file
  vecchio sta proprio nel path configurato.
- `SSL_CRT`: un certificato vero salvato con un altro nome non viene trovato, e al suo posto
  ne nasce uno autofirmato.
- `VHOST` vale `terminali.conf`: un vhost esistente con un altro nome non viene sostituito ma
  *affiancato*. Due server sulla 443, e nginx tiene il primo.

Metti i valori veri in `impostazioni.locale.conf`. Viene letto **prima** dei default, e git
non lo traccia:

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

Tieni la forma `: "${VAR:=valore}"`. L'ordine e' **ambiente > `impostazioni.locale.conf` >
`impostazioni.conf`**. I valori derivati (come `SSL_CRT` da `DOMINIO`) si calcolano dopo,
quindi seguono i valori veri e non i default.

Prima di installare, guarda: `./verifica.sh` non cambia niente e ti dice com'e' messa la
macchina, e `install.sh` stampa il riepilogo prima di toccare qualsiasi cosa.

### Manutenzione

| Cosa | Come |
|---|---|
| Cambiare numero di terminali | `N_TERM` in `impostazioni.conf`, poi `./install.sh --salta-pacchetti` |
| Ridurre `N_TERM` | le unit in piu' restano accese: `systemctl disable --now ttyd@8709` a mano |
| CA scaduta | `sudo certs/rinnova-ca.sh`: rifirma con la **stessa** chiave e lo stesso DN, i certificati client restano validi |
| Certificato server scaduto | rigeneralo con `certs/cert-server.sh`, o punta `SSL_CRT`/`SSL_KEY` a un certificato vero |
| Vedere cosa gira | `systemctl status 'ttyd@*'`, `runuser -u UTENTE -- tmux ls` |
| mTLS stretto o diagnostico | `VERIFICA_CLIENT` (`on` / `optional`), poi `./install.sh --salta-pacchetti` |
| Chiudere anche la porta 80 | `PROTEGGI_80` (`nome` / `default` / `no`), poi `./install.sh --salta-pacchetti` |
| Nomi dei tab legati all'utente | `PROFILI` (`si` / `no`), poi `./install.sh --salta-pacchetti` |
| Azzerare il profilo di qualcuno | `rm $DIR_PROFILI/<cn>.json`: al prossimo accesso si ricrea |
| Spegnere i nomi automatici per tutti | `set -g set-titles off` in `conf/tmux-terminali.conf`, poi `./install.sh --salta-pacchetti` |
| Aggiungere i favicon | `design/esporta.py` li genera in `conf/icone/` dal marchio in `design/marchio/`, poi `./install.sh --salta-pacchetti` |
| Cambiare o aggiungere un'icona | `design/icone/icone.json`, poi `design/esporta.py --solo-icone` e `./install.sh --salta-pacchetti` (vedi `design/ICONE-E-MARCHIO.md`) |
| Controllare un'installazione | `sudo ./verifica.sh`: non cambia niente, e guarda anche il lato in chiaro |

## Trappole, tutte verificate sul campo

**mTLS: `on` o `optional`.** Lo decide `VERIFICA_CLIENT` in `impostazioni.conf`. Il default e'
`on`.

- **`on`**: il certificato lo chiede nginx durante l'handshake TLS. Senza, la richiesta muore
  con `400 No required SSL certificate was sent` e non arriva a nessuna `location`.
- **`optional`**: la connessione entra, e la respinge il vhost con
  `if ($ssl_client_verify != SUCCESS) { return 403; }`. La pagina ti dice *quale* caso e':
  certificato assente, scaduto o di un'altra CA. Utile quando sei chiuso fuori dal tuo server.

Con `optional`, **quel controllo e' l'unica protezione**. Se lo togli, chiunque arriva sulla
443 ha una shell: scrivibile, e con `sudo` se l'utente ce l'ha. E' successo davvero, per mezza
giornata. Per questo il controllo si genera anche con `on`: li' non scatta mai, ma passare a
`optional` resta una variabile sola.

**La porta 80 non e' tua.** L'mTLS difende la 443, non la 80. La configurazione di serie di
nginx ha

```nginx
server { listen 80; server_name _; root /usr/share/nginx/html; }
```

che serve **lo stesso webroot della dashboard**, in chiaro e senza chiedere niente. I
terminali li' non ci sono (`/term0/` e gli altri danno 404). Esce la pagina della dashboard e,
peggio, *qualunque file lasciato nel webroot*. `PROTEGGI_80` decide quanto chiudere:

| valore | cosa installa | copre |
|---|---|---|
| `nome` (default) | un server sulla 80 per il solo `$DOMINIO`, `301` verso https | `http://tuo.host/…` |
| `default` | il precedente, piu' `listen 80 default_server` che risponde `444` | anche l'IP nudo e gli `Host:` sconosciuti |
| `no` | niente | niente |

Su una macchina dedicata usa `default`. Non e' il default perche' e' l'unico pezzo che cambia
la macchina *fuori* dai terminali: su un server condiviso zittisce gli altri siti http senza un
`server_name` proprio.

Nessuno dei tre e' la vera protezione. Quella e': **nel webroot non devono mai stare chiavi o
certificati**. Vedi la prossima.

**Mai il `.p12` nel webroot.** Sembra comodo per importarlo dal telefono. Ma il webroot lo
serve anche la porta 80 di serie, in chiaro e senza certificato. Un `.p12` li' e' l'unica
chiave del servizio pubblicata su internet, con una passphrase che chiunque puo' provare a
indovinare offline, con calma. Per questo gli script lo scrivono in `/root/certs-client` con
permessi `0600`. `install.sh` si rifiuta di partire se nel webroot trova un `.p12`, `.key`,
`.pem`, `.crt` o `.csr`. `verifica.sh` controlla lo stesso, e stampa l'URL http da cui il file
si scarica.

**SELinux.** In modalita' **enforcing** nginx non puo' collegarsi a ttyd: `proxy_pass` da' 502
e in `audit.log` compare `name_connect`. `install.sh` mette `httpd_can_network_connect=1`. Sul
server originale non si vedeva perche' era in *Permissive*.

**ttyd e' in sola lettura di serie**, dalla 1.7.0. Senza `-W` vedi il terminale ma non puoi
scrivere. `-W` e' nella unit.

**`tmux new-session -A`** si attacca alla sessione se c'e', se no la crea. E' questo che
rende il terminale persistente. Il rovescio: `exit` chiude la sessione per sempre, e al
prossimo collegamento ne trovi una nuova e vuota.

**`KillMode=process` nella unit. Non e' un dettaglio.** Il server tmux lo avvia il *primo*
`tmux new-session`, quindi finisce nel cgroup di quella unit `ttyd@`. Col `KillMode` di serie
(`control-group`), fermare quella unit uccide tutto il suo cgroup: il server tmux e con lui
**tutte** le sessioni, non solo la sua. `install.sh` fa `restart` su ogni porta, e cosi'
cancellava il lavoro in tutti i terminali. Su una macchina vera: dieci sessioni, un solo server
tmux, nel cgroup di `ttyd@8708`. Un `systemctl restart ttyd@8708` le avrebbe chiuse tutte.

Con `KillMode=process` si ferma solo `ttyd`: tmux resta, e `-A` ritrova la sessione. **Se
aggiorni un'installazione vecchia**, il primo `install.sh` azzera ancora tutto. Installa la
unit nuova e fai solo `systemctl daemon-reload`, senza `restart`: la `KillMode` nuova vale dal
riavvio successivo.

**Timeout della websocket.** Il vhost mette `proxy_read_timeout 1d`. Col default di 60s nginx
chiude una sessione ferma, e il terminale va in riconnessione. Sull'originale non si notava
perche' la barra di stato di tmux si aggiorna ogni 15s e tiene viva la linea: funzionava per
caso.

**I favicon si generano da quello che c'e'.** `index.html` ha un `<link>` per ogni icona
davvero presente nel webroot (o in `conf/icone/`, da cui `install.sh` le copia). Un `<link>`
a un file che manca e' un 404 a ogni pagina. I binari non stanno nel repo: un server che li ha
gia' se li tiene anche dopo un rilancio.

**I profili non hanno bisogno di un backend.** Nomi dei tab, terminali aperti, il loro ordine
e la griglia stanno in un JSON per identita'. Lo serve e lo scrive nginx: su Rocky
`ngx_http_dav_module` e' compilato dentro, quindi il `PUT` lo accetta da solo. Niente processi
in piu', niente porte nuove, tutto dietro l'mTLS che c'e' gia'.

L'identita' e' il **CN del certificato client**. nginx non ha una variabile per il CN, solo il
DN intero: lo tira fuori una `map`. Attenzione al formato: `$ssl_client_s_dn` e' in RFC2253,
che scrive il DN *al contrario*, e un eventuale `emailAddress` viene **prima** del CN. Per
questo la regex lo cerca in mezzo alla stringa, non in testa.

Il nome del file deve essere esattamente l'identita'. Lo garantisce un backreference in una
seconda `map`:

```nginx
map "$cn_client:$uri" $profilo_mio {
    default                                   0;
    "~^([A-Za-z0-9._-]+):/profili/\1\.json$"  1;
}
```

Cosi' il percorso che manda il browser non conta: leggere o scrivere il profilo di un altro
da' 403. Un CN assente, vuoto, troppo lungo o con caratteri che non stanno in un nome di file
diventa un'identita' vuota: niente lettura, niente scrittura.

Da ricordare:

- **Un certificato per dispositivo = un profilo per dispositivo.** Due browser con lo stesso
  `.p12` condividono i nomi. Telefono e portatile con certificati diversi restano separati.
- **Vince l'ultimo che scrive, non l'ultimo che carica.** Con due browser aperti non c'e'
  fusione: chi rinomina per ultimo sovrascrive. "Ultimo" lo decide una data. Ogni modifica
  locale lascia un timestamp in `localStorage`, e la `PUT` lo porta nel campo `agg`. Al
  caricamento, se la data locale e' piu' recente di quella del profilo, vince la cache e sale
  sul server. Se no vince il profilo. Senza questo, ricaricare entro gli 800ms del debounce
  (o con una `PUT` rifiutata, o senza rete) riportava i nomi vecchi. Gli orologi di macchine
  diverse possono essere sfasati, ma il caso che conta (cambio qui, ricarico qui) e' sullo
  stesso browser. In piu' una `PUT` in attesa parte subito su `pagehide` e quando la pagina
  va in secondo piano, con `keepalive` (se no il browser la annulla).

**Quando la sessione muore, il nome torna di serie anche sul server.** Prima restava solo nel
browser, e per un motivo: l'unico indizio era il "Connection Closed" di ttyd, e con quello un
riavvio di nginx avrebbe cancellato i nomi in tutti i browser di quella identita'. Adesso
l'indizio e' il `[exited]` del client tmux, che c'e' solo se la sessione e' finita davvero. E
una sessione finita e' finita per tutti i dispositivi. Lo stesso vale per la chiusura del tab.

**Come si sa che la shell e' morta.** ttyd scrive "Connection Closed" sia quando la sessione
finisce, sia quando cade solo la linea. Nel primo caso il tab si chiude; nel secondo bisogna
aspettare che ttyd si riattacchi. Si guarda quindi cosa lascia sullo schermo il **client
tmux** quando esce: lascia lo schermo alternativo (`ESC [ ? 1049 l`), pulisce e stampa

```
[exited]
```

La riga finisce nel buffer di `xterm.js`, e si legge da li'. Verificato su **tmux 3.2a**
registrando il pty di un client vero. Una linea caduta non la stampa: il processo viene
ucciso, e lo schermo resta com'era. Il controllo si ripete per un paio di secondi dopo
l'avviso di ttyd, perche' `xterm.js` scrive in modo asincrono. Se una versione di tmux non
stampasse quella riga, il tab resta aperto e lo chiudi col `✕`: perdi la comodita', non il
lavoro.

**Come si sa se la copy-mode e' attiva.** Non contando i click sul bottone: con una tastiera
vera si entra e si esce da soli. Si guarda cosa **disegna tmux**: in copy-mode scrive
`[riga/totale]` in alto a destra del pannello, e quel disegno finisce nel buffer di xterm.js.
Verificato su un client tmux vero: entrando compare `[0/179]`.

- `capture-pane` **non** lo mostra: cattura il pannello, ma l'indicatore lo disegna il
  client. Per vederlo registra il pty di un client attaccato
  (`script -f ... -c "tmux attach -t ..."`).
- `[n/m]` da solo non basta: una barra di avanzamento che stampa `[1/10]` accenderebbe la
  spia. L'indicatore di tmux usa `mode-style`, di serie `bg=yellow`, quindi si controlla anche
  lo **sfondo** delle celle.
- Per uscire si manda **Esc**, non `q`. Esc chiude la copy-mode in tutte e due le tabelle di
  tmux (`copy-mode` e `copy-mode-vi`), e fuori dalla copy-mode non fa danni. `q` invece
  scriverebbe una lettera nella shell.

**Le frecce hanno due forme.** Col modo cursore "applicazione" (DECCKM, lo accendono `vi` e i
programmi a tutto schermo) una freccia e' `ESC O A`. Negli altri casi e' `ESC [ A`. Per questo
la barra dei tasti guarda `term.modes.applicationCursorKeysMode` prima di scegliere. `Esc` e'
`ESC`, `Tab` e' `HT` (0x09), `PagSu`/`PagGiu` sono `ESC [ 5~` e `ESC [ 6~`: le stesse
sequenze di xterm.js.

**Copia-incolla e OSC 52.** Nel bundle di ttyd **1.7.7 di EPEL**, xterm.js gestisce gli OSC 0,
1, 2, 4, 8, 10-12, 104, 110-112 e 1337. Il **52**, quello con cui un programma chiede "metti
questo negli appunti", **manca**: la richiesta spariva senza errori. Lo aggiunge la dashboard,
con `term.parser.registerOscHandler(52, …)`. tmux non va toccato: Claude Code copia con
`tmux load-buffer -w`, e col `-w` e' tmux a mandare `ESC ] 52 ; ; <base64> BEL` al client,
anche con `set-clipboard` al valore di serie `external`. Verificato su un client tmux 3.5a, e
sulla catena intera (tmux → ttyd 1.7.7 → xterm.js → gestore) con Chrome headless. Solo
scrittura: la lettura (`?`) si ignora. Il prezzo e' quello solito dell'OSC 52: quello che esce
in un terminale puo' scrivere negli appunti, come in kitty, WezTerm o iTerm2. Per i programmi
che non copiano da soli c'e' Congela (`Ctrl+Alt+C`).

## Licenza

Licenza Gratitudine & Gentilezza Casuale — la licenza MIT, con un augurio.
Giuridicamente e' MIT puro: dove serve un identificativo di licenza, dichiara
`MIT`. Vedi [LICENSE](LICENSE) (inglese, fa fede) e
[LICENSE.it.md](LICENSE.it.md) (traduzione italiana di cortesia).
