#!/bin/bash
# Installa da zero l'ambiente "terminali web": N istanze ttyd, ognuna attaccata
# alla propria sessione tmux persistente, dietro un nginx che fa mTLS, piu' la
# dashboard a tab. Idempotente: si puo' rilanciare per applicare una modifica
# ai modelli in conf/ o un cambio di N_TERM.
#
#   ./install.sh                 tutto
#   ./install.sh --salta-pacchetti   salta dnf (rilancio veloce)
#   ./install.sh --force         certificato server autofirmato ad hoc, anche
#                                se nginx ne ha gia' uno valido per DOMINIO
#   ./install.sh --aiuto
#
# Testato su Rocky Linux 9 e Fedora 39. Su Debian/Ubuntu i pacchetti e i path dei
# certificati cambiano: vedi README.md. [RR]
set -euo pipefail

RADICE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALTA_PACCHETTI=no
FORZA_CERT=no

for a in "$@"; do
    case "$a" in
        --salta-pacchetti) SALTA_PACCHETTI=si ;;
        --force) FORZA_CERT=si ;;
        --aiuto|-h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
        *) echo "opzione sconosciuta: $a" >&2; exit 1 ;;
    esac
done

# comune.inc legge impostazioni.conf e porta stessaCoppia.
# shellcheck source=/dev/null
. "$RADICE/certs/comune.inc"

titolo() { echo; echo "=== $* ==="; }
[ "$(id -u)" -eq 0 ] || { echo "Serve root." >&2; exit 1; }
LOCALE="$RADICE/impostazioni.locale.conf"

# Un DOMINIO senza punto e' quasi sempre `hostname -f` di una macchina che non
# ha un FQDN (qui: "mine"): nessun certificato vero lo copre e nessun browser
# ci arriva. Si chiede, si salva negli override locali e si riparte, cosi' i
# valori derivati (SSL_CRT, ...) si ricalcolano sul nome giusto. [RR]
case "$DOMINIO" in
    *.*) ;;
    *)  if [ -t 0 ]; then
            read -r -p "DOMINIO e' '$DOMINIO', non e' un nome pubblico. Con che nome si raggiunge il servizio? " D
            case "$D" in *.*) ;; *) echo "ERRORE: '$D' non e' un nome di dominio." >&2; exit 1 ;; esac
            echo ": \"\${DOMINIO:=$D}\"" >> "$LOCALE"
            echo "salvato in $LOCALE"
            exec "$0" "$@"
        fi
        echo "ERRORE: DOMINIO='$DOMINIO' non e' un nome pubblico. Mettilo in $LOCALE:" >&2
        echo "  : \"\${DOMINIO:=term.esempio.it}\"" >&2
        exit 1 ;;
esac

# PREFISSO: un percorso assoluto senza barra finale, fatto di pezzi innocui.
# Finisce dentro location, regex della map e JavaScript: niente spazi, niente
# caratteri che in uno di questi tre posti vogliano dire altro.
if [ -n "$PREFISSO" ] && ! [[ "$PREFISSO" =~ ^(/[A-Za-z0-9._-]+)+$ ]]; then
    echo "ERRORE: PREFISSO deve essere tipo /term (adesso: '$PREFISSO')." >&2
    exit 1
fi

# --force: il certificato e' quello ad hoc sul path di default, anche se gli
# override locali puntano a un altro. export perche' cert-server.sh rilegge
# impostazioni.conf, e l'ambiente vince sugli override.
if [ "$FORZA_CERT" = si ]; then
    export SSL_CRT="/etc/nginx/ssl/$DOMINIO.crt" SSL_KEY="/etc/nginx/ssl/$DOMINIO.key"
fi

PORTE=()
for ((i = 0; i < N_TERM; i++)); do PORTE+=( $((PORTA_BASE + i)) ); done

# Un solo temporaneo per tutto lo script, con una sola trap: due `trap ... EXIT`
# non si sommano, il secondo sostituisce il primo e quello di prima resterebbe
# a terra. [RR]
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

titolo "Riepilogo"
cat <<RIEP
dominio        : $DOMINIO
utente shell   : $UTENTE:$GRUPPO
terminali      : $N_TERM  (porte ${PORTE[0]}-${PORTE[-1]}, path /term0/ ... /term$((N_TERM-1))/)
webroot        : $WEBROOT
$(if [ -n "$PREFISSO" ]; then
echo "montato in     : https://$DOMINIO$PREFISSO/  (dentro il server{} del sito)"
echo "location in    : $INCLUDE_PATH"
echo "upstream/map in: $VHOST"
else
echo "vhost          : $VHOST"
echo "cert server    : $SSL_CRT"
echo "verifica client: ssl_verify_client $VERIFICA_CLIENT"
fi)
CA client      : $CA_CRT
cert client in : $CERT_CLIENT_DIR
porta 80       : $PROTEGGI_80
profili utente : $PROFILI$([ "$PROFILI" = si ] && echo "  ($DIR_PROFILI)")
RIEP

case "$VERIFICA_CLIENT" in
    on) ;;
    optional) echo "NOTA: VERIFICA_CLIENT=optional. Chi protegge il servizio e' il controllo su \$ssl_client_verify nel vhost: non toglierlo." ;;
    *) echo "ERRORE: VERIFICA_CLIENT deve essere 'on' oppure 'optional', non '$VERIFICA_CLIENT'." >&2; exit 1 ;;
esac

case "$PROTEGGI_80" in
    nome)    ;;
    default) ;;
    no) echo "NOTA: PROTEGGI_80=no. La 80 resta come sta: se il default server di nginx serve $WEBROOT, la dashboard e' leggibile in chiaro." ;;
    *)  echo "ERRORE: PROTEGGI_80 deve essere 'nome', 'default' oppure 'no', non '$PROTEGGI_80'." >&2; exit 1 ;;
esac

case "$PROFILI" in
    si) ;;
    no) echo "NOTA: PROFILI=no. Nomi e ordine dei tab restano in localStorage, cioe' per browser." ;;
    *)  echo "ERRORE: PROFILI deve essere 'si' oppure 'no', non '$PROFILI'." >&2; exit 1 ;;
esac

# Il path nell'URL e' fisso (/profili/<cn>.json) e sta scritto nella dashboard:
# la directory si puo' spostare, l'ultimo pezzo del nome no.
if [ "$PROFILI" = si ] && [ "$(basename "$DIR_PROFILI")" != profili ]; then
    echo "ERRORE: DIR_PROFILI deve finire con /profili (adesso: $DIR_PROFILI)." >&2
    echo "L'ultimo pezzo e' anche il path nell'URL, che la dashboard ha scritto dentro." >&2
    exit 1
fi

# L'utente delle shell deve esistere: ttyd non lo crea e le unit fallirebbero
# a raffica con Restart=always.
id "$UTENTE" >/dev/null 2>&1 || { echo "ERRORE: l'utente '$UTENTE' non esiste su questo server." >&2; exit 1; }
[ "$UTENTE" = root ] && echo "ATTENZIONE: le shell girano come root. Un errore nell'mTLS diventa una root shell aperta."

# Materiale crittografico nel WEBROOT: si controlla PRIMA di toccare qualsiasi
# cosa. Il WEBROOT e' servito anche dal default server della 80, in chiaro e
# senza mTLS, quindi un .p12 lasciato qui "per comodita' di import dal
# telefono" e' il certificato client pubblicato su internet -- ed e' l'unica
# autenticazione del servizio. Non si sposta da soli: e' roba di chi l'ha
# messa, e va deciso a mano dove finisce.
CHIAVI=()
if [ -d "$WEBROOT" ]; then
    while IFS= read -r f; do CHIAVI+=( "$f" ); done < <(
        find "$WEBROOT" -maxdepth 3 -type f \
             \( -name '*.p12' -o -name '*.pfx' -o -name '*.key' -o -name '*.pem' \
                -o -name '*.crt' -o -name '*.csr' \) 2>/dev/null
    )
fi
if [ "${#CHIAVI[@]}" -gt 0 ]; then
    echo >&2
    echo "ERRORE: nel webroot ci sono certificati o chiavi:" >&2
    printf '  %s\n' "${CHIAVI[@]}" >&2
    # heredoc non quotato: il path giusto dove spostarli e' CERT_CLIENT_DIR,
    # che su un'installazione adottata non e' quello di default.
    cat >&2 <<MOTIVO

Il webroot e' pubblico: la configurazione di serie di nginx lo serve anche
sulla porta 80, in chiaro e senza chiedere alcun certificato client. Un .p12
lasciato qui e' la chiave di casa sotto lo zerbino.

Spostali fuori (gli emessi da qui stanno in $CERT_CLIENT_DIR, 0600) e rilancia:
  mv <file> $CERT_CLIENT_DIR/
MOTIVO
    exit 1
fi

# Modo PREFISSO: il server{} che ci ospita deve esistere e fidarsi della
# stessa CA con cui si emettono i certificati client, altrimenti i terminali
# sarebbero montati ma nessun certificato nostro passerebbe. Si controlla
# PRIMA di installare: e' un errore di configurazione, non di pacchetti.
# Si cerca il file in conf.d con `server_name ... $DOMINIO` e una 443: vale
# per il caso normale di un file per sito. [RR]
if [ -n "$PREFISSO" ]; then
    SITO=""
    for f in /etc/nginx/conf.d/*.conf; do
        [ "$f" = "$VHOST" ] && continue
        grep -qE "^[[:space:]]*server_name[^;]*[[:space:]]${DOMINIO//./\\.}[[:space:];]" "$f" \
            && grep -qE '^[[:space:]]*listen[^;]*443' "$f" && { SITO=$f; break; }
    done
    [ -n "$SITO" ] || { echo "ERRORE: nessun file in /etc/nginx/conf.d ha un server{} https per $DOMINIO." >&2; exit 1; }
    CA_SITO=$(awk '$1=="ssl_client_certificate"{sub(/;.*/,"",$2); print $2; exit}' "$SITO")
    VERIFICA_SITO=$(awk '$1=="ssl_verify_client"{sub(/;.*/,"",$2); print $2; exit}' "$SITO")
    case "$VERIFICA_SITO" in
        on|optional) ;;
        *) echo "ERRORE: $SITO non chiede certificati client (ssl_verify_client '${VERIFICA_SITO:-assente}')." >&2
           echo "Serve 'optional' (o 'on') e una ssl_client_certificate nel server{} di $DOMINIO." >&2
           exit 1 ;;
    esac
    if [ "$CA_SITO" != "$CA_CRT" ]; then
        echo "ERRORE: il sito si fida della CA $CA_SITO, ma CA_CRT e' $CA_CRT." >&2
        echo "Con il PREFISSO la CA e' quella del sito. In $LOCALE:" >&2
        echo "  : \"\${CA_CRT:=$CA_SITO}\"" >&2
        echo "  : \"\${CA_KEY:=<la sua chiave>}\"" >&2
        exit 1
    fi
    echo "sito ospite    : $SITO (ssl_verify_client $VERIFICA_SITO)"
fi

# --- 1. pacchetti -------------------------------------------------------------
if [ "$SALTA_PACCHETTI" = no ]; then
    titolo "Pacchetti"
    # ttyd sta in EPEL su Rocky/RHEL; Fedora lo ha nei repo base e
    # epel-release non esiste proprio (dnf fallirebbe e set -e chiuderebbe
    # tutto qui). Si chiede EPEL solo se ttyd non e' gia' installabile.
    rpm -q epel-release >/dev/null 2>&1 || dnf -q list ttyd >/dev/null 2>&1 \
        || dnf install -y epel-release
    dnf install -y ttyd tmux nginx openssl
else
    titolo "Pacchetti (saltati)"
    for c in ttyd tmux nginx openssl; do
        command -v "$c" >/dev/null || { echo "ERRORE: manca $c" >&2; exit 1; }
    done
fi
echo "ttyd  : $(ttyd --version 2>&1 | head -1)"
echo "tmux  : $(tmux -V)"
echo "nginx : $(nginx -v 2>&1)"

# --- 2. certificati -----------------------------------------------------------
titolo "CA dei certificati client"
"$RADICE/certs/crea-ca.sh"

if [ -n "$PREFISSO" ]; then
titolo "Certificato TLS del server (quello del sito, non si tocca)"
else
titolo "Certificato TLS del server"
# Se il certificato configurato non c'e' ancora, si guarda se il server ne ha
# gia' uno valido per DOMINIO (quelli che nginx usa, piu' Let's Encrypt): un
# autofirmato accanto a un certificato vero e' un avviso nel browser per
# niente. Si chiede, e la scelta finisce in impostazioni.locale.conf, cosi' il
# rilancio non richiede. --force salta tutto questo. [RR]
if [ "$FORZA_CERT" = no ] && ! { [ -f "$SSL_CRT" ] && [ -f "$SSL_KEY" ]; }; then
    CAND=()
    while read -r c k; do
        [ -f "$c" ] && [ -f "$k" ] || continue
        openssl x509 -in "$c" -noout -checkend 0 >/dev/null 2>&1 || continue
        openssl x509 -in "$c" -noout -checkhost "$DOMINIO" 2>/dev/null | grep -q ' does match' || continue
        stessaCoppia "$c" "$k" || continue
        CAND+=( "$c $k" )
    done < <(
        { nginx -T 2>/dev/null | awk '$1=="ssl_certificate"{c=$2} $1=="ssl_certificate_key"{sub(/;.*/,"",c); k=$2; sub(/;.*/,"",k); print c, k}'
          for d in /etc/letsencrypt/live/*/; do echo "${d}fullchain.pem ${d}privkey.pem"; done
        } | sort -u
    )
    if [ "${#CAND[@]}" -gt 0 ]; then
        echo "Sul server c'e' gia' un certificato valido per $DOMINIO:"
        for i in "${!CAND[@]}"; do
            set -- ${CAND[$i]}
            printf '  %s) %s  (scade %s)\n' "$((i + 1))" "$1" "$(openssl x509 -in "$1" -noout -enddate | cut -d= -f2)"
        done
        SCELTA=1
        if [ -t 0 ]; then
            read -r -p "Quale uso? [1-${#CAND[@]}, n = autofirmato ad hoc] (1) " SCELTA
            SCELTA=${SCELTA:-1}
        else
            echo "(niente terminale: uso il primo; --force per l'autofirmato)"
        fi
        if [[ "$SCELTA" =~ ^[0-9]+$ ]] && [ "$SCELTA" -ge 1 ] && [ "$SCELTA" -le "${#CAND[@]}" ]; then
            set -- ${CAND[$((SCELTA - 1))]}
            export SSL_CRT="$1" SSL_KEY="$2"
            printf ': "${SSL_CRT:=%s}"\n: "${SSL_KEY:=%s}"\n' "$1" "$2" >> "$LOCALE"
            echo "uso $SSL_CRT (salvato in $LOCALE)"
        fi
    fi
fi
"$RADICE/certs/cert-server.sh"
fi

# --- 3. istanze ttyd ----------------------------------------------------------
titolo "Unit ttyd@"
# I titoli: senza questo file tmux tiene per se' il titolo che scrivono le
# applicazioni e in pagina non arriva. Va installato PRIMA delle unit, che lo
# leggono all'avvio.
install -m 644 "$RADICE/conf/tmux-terminali.conf" /etc/tmux-terminali.conf
echo "  /etc/tmux-terminali.conf: titoli dei terminali verso la pagina"
sed -e "s|@UTENTE@|$UTENTE|g" -e "s|@GRUPPO@|$GRUPPO|g" \
    "$RADICE/conf/ttyd@.service.tmpl" > /etc/systemd/system/ttyd@.service
chmod 644 /etc/systemd/system/ttyd@.service
systemctl daemon-reload
for p in "${PORTE[@]}"; do
    systemctl enable "ttyd@$p" >/dev/null
    # restart e non start: un rilancio dopo un cambio di unit deve ripartire
    # con la configurazione nuova.
    #
    # ATTENZIONE, e non e' teoria: le sessioni tmux sopravvivono SOLO se la
    # unit ha KillMode=process. Il server tmux finisce nel cgroup della prima
    # unit ttyd che parte, e col KillMode di default (control-group) questo
    # restart lo ucciderebbe insieme a TUTTE le sessioni, non solo a quella
    # della porta. Se stai aggiornando un'installazione nata prima di questa
    # riga, il primo `install.sh` e' ancora quello che azzera tutto: fai
    # `systemctl daemon-reload` senza restart, e lascia che la KillMode nuova
    # valga dal riavvio successivo. [RR]
    systemctl restart "ttyd@$p"
done
sleep 1
for p in "${PORTE[@]}"; do
    printf '  ttyd@%s : %s\n' "$p" "$(systemctl is-active "ttyd@$p")"
done

# --- 4. dashboard -------------------------------------------------------------
titolo "Dashboard"
# Un terminale per riga, non tutti su una riga sola: questo pezzo si finisce a
# leggere nel "vedi sorgente" del browser quando un tab non va, ed e' l'unico
# punto della pagina che dice quanti terminali ci sono. Si genera su file
# perche' sed non sostituisce a capo dentro una s|||. [RR]
{
    echo "    var TERMINALS = ["
    for ((i = 0; i < N_TERM; i++)); do
        VIRGOLA=","; [ "$i" -eq "$((N_TERM - 1))" ] && VIRGOLA=""
        printf "      { id: %s, label: 'Term %s' }%s\n" "$i" "$i" "$VIRGOLA"
    done
    echo "    ];"
} > "$TMP/terminals"

install -d -m 755 "$WEBROOT"

# Icone: se conf/icone/ contiene qualcosa lo si copia nel WEBROOT, poi si
# genera un <link> per ogni file che ESISTE davvero (nel repo i .png non ci
# sono, ma su un server che le ha gia' i link vanno rimessi comunque: un
# install.sh che li perde degrada la pagina a ogni rilancio). Un <link> verso
# un file assente sarebbe un 404 a ogni caricamento, quindi si guarda il
# disco e non un elenco fisso. [RR]
if [ -d "$RADICE/conf/icone" ]; then
    for f in "$RADICE/conf/icone"/*; do
        [ -f "$f" ] || continue
        case "${f##*/}" in LEGGIMI.md|README*) continue ;; esac
        install -m 644 "$f" "$WEBROOT/${f##*/}"
    done
fi

: > "$TMP/icone"
# favicon.ico non ha un <link>: i browser lo chiedono da soli su /favicon.ico.
# `|| return 0` e non `&& printf`: con set -e una funzione il cui ultimo
# comando fallisce fa morire lo script, e qui il file mancante e' la norma.
icona() { [ -f "$WEBROOT/$1" ] || return 0; printf '  %s\n' "$2" >> "$TMP/icone"; }
icona apple-touch-icon.png "<link rel=\"apple-touch-icon\" sizes=\"180x180\" href=\"$PREFISSO/apple-touch-icon.png\">"
icona favicon-32x32.png    "<link rel=\"icon\" type=\"image/png\" sizes=\"32x32\" href=\"$PREFISSO/favicon-32x32.png\">"
icona favicon-16x16.png    "<link rel=\"icon\" type=\"image/png\" sizes=\"16x16\" href=\"$PREFISSO/favicon-16x16.png\">"
icona site.webmanifest     "<link rel=\"manifest\" href=\"$PREFISSO/site.webmanifest\">"
N_ICONE=$(wc -l < "$TMP/icone")

# La licenza va dentro la pagina, nel <pre> nascosto che il bottone dell'aiuto
# mostra: il testo e' quello del file LICENSE, non una copia nel modello che si
# allontanerebbe dall'originale al primo ritocco. Finisce dentro dell'HTML,
# quindi va escapato -- la & del titolo, da sola, basterebbe a romperlo. [RR]
if [ -f "$RADICE/LICENSE" ]; then
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        "$RADICE/LICENSE" > "$TMP/licenza"
else
    printf 'Licenza MIT: il testo sta nel file LICENSE del progetto.\n' > "$TMP/licenza"
fi

[ -f "$WEBROOT/index.html" ] && cp -p "$WEBROOT/index.html" "$WEBROOT/index.html.bak-$(date +%Y%m%d%H%M%S)"
sed -e "/@ICONE@/r $TMP/icone" -e "/@ICONE@/d" \
    -e "/@TERMINALS@/r $TMP/terminals" -e "/@TERMINALS@/d" \
    -e "/@LICENZA@/r $TMP/licenza" -e "/@LICENZA@/d" \
    -e "s|@TITOLO@|$TITOLO|g" -e "s|@PREFISSO@|$PREFISSO|g" \
    "$RADICE/conf/index.html.tmpl" > "$WEBROOT/index.html"
chmod 644 "$WEBROOT/index.html"
echo "$WEBROOT/index.html: $N_TERM terminali, $N_ICONE icone"

# --- 5. vhost nginx -----------------------------------------------------------
titolo "nginx"
for p in "${PORTE[@]}"; do
    echo "upstream ttyd_$p { server 127.0.0.1:$p; }" >> "$TMP/upstream"
done
# Il controllo dell'mTLS in ogni location: nel vhost nostro c'e' gia' a
# livello di server (e questo non scatta mai), col PREFISSO e' l'unico.
for ((i = 0; i < N_TERM; i++)); do
    printf '    location %s/term%s/ { if ($ssl_client_verify != SUCCESS) { return 403; } proxy_pass http://ttyd_%s/; }\n' \
        "$PREFISSO" "$i" "$((PORTA_BASE + i))" >> "$TMP/location"
done

# Profili: i due pezzi si aggiungono solo se accesi. Le map stanno a livello
# http (fuori dal server), le location dentro: sono due segnaposto separati.
if [ "$PROFILI" = si ]; then
    sed -e "s|@PREFISSO@|$PREFISSO|g" "$RADICE/conf/nginx-profili-map.inc" > "$TMP/profilimap"
    sed -e "s|@DIR_PROFILI@|$DIR_PROFILI|g" -e "s|@PREFISSO@|$PREFISSO|g" \
        "$RADICE/conf/nginx-profili.inc" > "$TMP/profili"
else
    : > "$TMP/profilimap"; : > "$TMP/profili"
fi

# Il blocco multiriga si inserisce col trucco classico di sed: "r file"
# accoda il contenuto dopo la riga del segnaposto, "d" cancella il segnaposto.
if [ -n "$PREFISSO" ]; then
    # upstream e map sono roba del livello http: vanno in conf.d, che nginx
    # include li'. Le location vanno nel server{} del sito, via include.
    { echo "# Terminali web (modo PREFISSO): upstream e map. Generato da install.sh, le"
      echo "# location stanno in $INCLUDE_PATH, incluso dal server{} di $DOMINIO."
      cat "$TMP/upstream" "$TMP/profilimap"; } > "$TMP/vhost.conf"
    sed -e "/@BLOCCHI_LOCATION@/r $TMP/location" -e "/@BLOCCHI_LOCATION@/d" \
        -e "/@BLOCCHI_PROFILI@/r $TMP/profili" -e "/@BLOCCHI_PROFILI@/d" \
        -e "s|@PREFISSO@|$PREFISSO|g" -e "s|@WEBROOT@|$WEBROOT|g" \
        -e "s|@INCLUDE_PATH@|$INCLUDE_PATH|g" \
        "$RADICE/conf/nginx-terminali-path.inc.tmpl" > "$TMP/path.inc"
    [ -f "$INCLUDE_PATH" ] && cp -p "$INCLUDE_PATH" "$INCLUDE_PATH.bak-$(date +%Y%m%d%H%M%S)"
    install -m 644 -o root -g root "$TMP/path.inc" "$INCLUDE_PATH"
else
sed -e "/@BLOCCHI_UPSTREAM@/r $TMP/upstream" -e "/@BLOCCHI_UPSTREAM@/d" \
    -e "/@BLOCCHI_LOCATION@/r $TMP/location" -e "/@BLOCCHI_LOCATION@/d" \
    -e "/@BLOCCHI_PROFILI_MAP@/r $TMP/profilimap" -e "/@BLOCCHI_PROFILI_MAP@/d" \
    -e "/@BLOCCHI_PROFILI@/r $TMP/profili" -e "/@BLOCCHI_PROFILI@/d" \
    -e "s|@DOMINIO@|$DOMINIO|g" -e "s|@SSL_CRT@|$SSL_CRT|g" -e "s|@SSL_KEY@|$SSL_KEY|g" \
    -e "s|@CA_CRT@|$CA_CRT|g" -e "s|@WEBROOT@|$WEBROOT|g" \
    -e "s|@VERIFICA_CLIENT@|$VERIFICA_CLIENT|g" \
    "$RADICE/conf/nginx-terminali.conf.tmpl" > "$TMP/vhost.conf"
fi

[ -f "$VHOST" ] && cp -p "$VHOST" "$VHOST.bak-$(date +%Y%m%d%H%M%S)"
install -m 644 -o root -g root "$TMP/vhost.conf" "$VHOST"

# La riga include nel server{} del sito. E' il file di un altro progetto:
# si chiede, si fa il backup, e se nginx -t non regge si rimette com'era.
# Va subito dopo il server_name del blocco https: e' l'unico punto del file
# che si riconosce con certezza. [RR]
if [ -n "$PREFISSO" ]; then
    if grep -qF "include $INCLUDE_PATH;" "$SITO"; then
        echo "$SITO include gia' $INCLUDE_PATH"
    else
        RISP=n
        if [ -t 0 ]; then
            read -r -p "Aggiungo 'include $INCLUDE_PATH;' nel server{} https di $SITO? [S/n] " RISP
            RISP=${RISP:-s}
        fi
        case "$RISP" in
            [sSyY]*)
                BAK="$SITO.bak-$(date +%Y%m%d%H%M%S)"
                cp -p "$SITO" "$BAK"
                awk -v inc="$INCLUDE_PATH" -v dom="$DOMINIO" '
                    /^[[:space:]]*server[[:space:]]*\{/ { ssl = 0 }
                    /^[[:space:]]*listen[^;]*443/        { ssl = 1 }
                    { print }
                    !fatto && ssl && $1 == "server_name" && index($0, dom) {
                        print "\t# terminali web sotto un path: vedi tmux-web-ui/install.sh"
                        print "\tinclude " inc ";"
                        fatto = 1
                    }' "$BAK" > "$SITO"
                if grep -qF "include $INCLUDE_PATH;" "$SITO" && nginx -t >/dev/null 2>&1; then
                    echo "aggiunto in $SITO (backup: $BAK)"
                else
                    cp -p "$BAK" "$SITO"
                    echo "ERRORE: con l'include nginx non regge, $SITO rimesso com'era:" >&2
                    nginx -t >&2 || true
                    exit 1
                fi ;;
            *)  echo "NOTA: aggiungi a mano nel server{} https di $DOMINIO, poi rilancia:"
                echo "  include $INCLUDE_PATH;" ;;
        esac
    fi
fi

# --- 6. porta 80 --------------------------------------------------------------
# Vedi conf/nginx-80.conf.tmpl per il perche'. Qui si sceglie solo quanto in
# largo si tira la coperta.
titolo "Porta 80 ($PROTEGGI_80)"
if [ -n "$PREFISSO" ]; then
    # La 80 di $DOMINIO e' del sito: un nostro server_name uguale litigherebbe.
    echo "modo PREFISSO: la 80 e' del sito, non la tocco"
elif [ "$PROTEGGI_80" = no ]; then
    # Idempotenza anche in marcia indietro: se un giro precedente aveva
    # installato il file, tornare a 'no' deve toglierlo davvero.
    if [ -f "$VHOST_80" ]; then
        mv "$VHOST_80" "$VHOST_80.bak-$(date +%Y%m%d%H%M%S)"
        echo "rimosso $VHOST_80 (backup accanto)"
    else
        echo "non tocco la 80"
    fi
else
    if [ "$PROTEGGI_80" = default ]; then
        cp "$RADICE/conf/nginx-80-default.inc" "$TMP/blocco80"
    else
        : > "$TMP/blocco80"
    fi
    sed -e "/@BLOCCO_DEFAULT@/r $TMP/blocco80" -e "/@BLOCCO_DEFAULT@/d" \
        -e "s|@DOMINIO@|$DOMINIO|g" \
        "$RADICE/conf/nginx-80.conf.tmpl" > "$TMP/vhost80.conf"

    [ -f "$VHOST_80" ] && cp -p "$VHOST_80" "$VHOST_80.bak-$(date +%Y%m%d%H%M%S)"
    install -m 644 -o root -g root "$TMP/vhost80.conf" "$VHOST_80"

    # Marcia indietro mirata. Il modo 'default' litiga con qualunque altro
    # vhost che dichiari default_server sulla 80 ("a duplicate default
    # server"), e perdere questa protezione e' meglio che lasciare nginx con
    # una configurazione che non ricarica: i terminali contano di piu'.
    # Ma si toglie SOLO se togliendolo la configurazione torna valida: se il
    # guasto e' altrove (per esempio nel vhost 443 appena scritto) il file
    # rientra al suo posto e l'errore vero lo mostra il passo 9. [RR]
    if nginx -t >/dev/null 2>&1; then
        echo "$VHOST_80 installato"
        [ "$PROTEGGI_80" = nome ] && echo "NOTA: copre http://$DOMINIO/, non l'IP nudo. Su una macchina dedicata usa PROTEGGI_80=default."
    else
        mv "$VHOST_80" "$TMP/vhost80.sospeso"
        if nginx -t >/dev/null 2>&1; then
            echo "ATTENZIONE: con $VHOST_80 nginx non regge, l'ho rimosso." >&2
            echo "Probabile causa: un altro vhost dichiara gia' default_server sulla 80." >&2
            echo "Riprova con PROTEGGI_80=nome. La 80 resta come era." >&2
        else
            # Il colpevole non e' questo file: rimettilo e lascia parlare
            # il controllo finale, che ha il messaggio giusto.
            mv "$TMP/vhost80.sospeso" "$VHOST_80"
            echo "NOTA: nginx -t fallisce, ma non per colpa di $VHOST_80 (vedi sotto)." >&2
        fi
    fi
fi

# --- 7. directory dei profili -------------------------------------------------
if [ "$PROFILI" = si ]; then
    titolo "Profili per utente"
    # Il controllo PRIMA di creare: il webroot e' pubblico sulla 80, e dei
    # profili la' dentro sarebbero preferenze di persone identificate
    # scaricabili in chiaro da chiunque.
    case "$DIR_PROFILI" in
        "$WEBROOT"|"$WEBROOT"/*)
            echo "ERRORE: DIR_PROFILI ($DIR_PROFILI) e' dentro il webroot," >&2
            echo "che e' servito in chiaro sulla porta 80. Mettila altrove." >&2
            exit 1 ;;
    esac
    # 0700 e proprietario nginx: la scrittura la fa nginx, e nessun altro
    # utente della macchina ha motivo di leggere le preferenze altrui.
    install -d -m 700 -o nginx -g nginx "$DIR_PROFILI"
    echo "$DIR_PROFILI  ($(stat -c '%U:%G %a' "$DIR_PROFILI"))"
fi

# --- 8. SELinux ---------------------------------------------------------------
# Con SELinux enforcing nginx NON puo' aprire connessioni di rete verso ttyd:
# il proxy_pass fallisce con 502 e in audit.log compare name_connect. Sulla
# macchina originale non si vedeva perche' e' in Permissive.
if command -v selinuxenabled >/dev/null && selinuxenabled; then
    titolo "SELinux ($(getenforce))"
    setsebool -P httpd_can_network_connect 1
    getsebool httpd_can_network_connect
    command -v restorecon >/dev/null && restorecon -R "$WEBROOT" || true

    # nginx deve poter SCRIVERE i profili: di serie una directory sotto
    # /var/lib ha un contesto che glielo vieta, e il PUT tornerebbe 500 con
    # un AVC in audit.log. Serve il tipo rw, non quello di sola lettura.
    if [ "$PROFILI" = si ] && command -v semanage >/dev/null; then
        semanage fcontext -a -t httpd_sys_rw_content_t "${DIR_PROFILI}(/.*)?" 2>/dev/null \
            || semanage fcontext -m -t httpd_sys_rw_content_t "${DIR_PROFILI}(/.*)?"
        command -v restorecon >/dev/null && restorecon -R "$DIR_PROFILI" || true
        echo "contesto SELinux dei profili: $(stat -c %C "$DIR_PROFILI" 2>/dev/null)"
    fi
fi

# --- 9. firewall --------------------------------------------------------------
if systemctl is-active --quiet firewalld 2>/dev/null; then
    titolo "firewalld"
    firewall-cmd --permanent --add-service=https >/dev/null
    firewall-cmd --reload >/dev/null
    echo "443/tcp aperta"
fi

# --- 10. avvio nginx -----------------------------------------------------------
nginx -t
systemctl enable nginx >/dev/null
systemctl reload nginx 2>/dev/null || systemctl restart nginx
echo "nginx: $(systemctl is-active nginx)"

# --- 11. primo certificato client ---------------------------------------------
if [ -f "$CERT_CLIENT_DIR/$CLIENT_INIZIALE.p12" ]; then
    titolo "Certificato client"
    echo "gia' presente: $CERT_CLIENT_DIR/$CLIENT_INIZIALE.p12"
else
    titolo "Primo certificato client"
    echo "openssl chiedera' una password per il .p12: serve al browser in fase di import."
    "$RADICE/certs/emetti-client.sh" "$CLIENT_INIZIALE"
fi

# --- 12. verifica -------------------------------------------------------------
"$RADICE/verifica.sh" || true

cat <<FINE

=== Fatto ===

Il servizio e' raggiungibile SOLO con un certificato client: senza, ogni
richiesta riceve la pagina che spiega cosa manca. Per entrare:

  1. porta via il .p12         scp root@$DOMINIO:$CERT_CLIENT_DIR/$CLIENT_INIZIALE.p12 .
  2. importalo nel browser     (Chrome: Impostazioni > Privacy > Certificati > I tuoi certificati)
  3. apri                      https://$DOMINIO$PREFISSO/

Un certificato in piu' per ogni dispositivo:

  certs/emetti-client.sh telefono-$UTENTE

FINE
