#!/bin/bash
# Installa da zero l'ambiente "terminali web": N istanze ttyd, ognuna attaccata
# alla propria sessione tmux persistente, dietro un nginx che fa mTLS, piu' la
# dashboard a tab. Idempotente: si puo' rilanciare per applicare una modifica
# ai modelli in conf/ o un cambio di N_TERM.
#
#   ./install.sh                 tutto
#   ./install.sh --salta-pacchetti   salta dnf (rilancio veloce)
#   ./install.sh --aiuto
#
# Testato su Rocky Linux 9. Su Debian/Ubuntu i pacchetti e i path dei
# certificati cambiano: vedi README.md. [RR]
set -euo pipefail

RADICE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALTA_PACCHETTI=no

for a in "$@"; do
    case "$a" in
        --salta-pacchetti) SALTA_PACCHETTI=si ;;
        --aiuto|-h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
        *) echo "opzione sconosciuta: $a" >&2; exit 1 ;;
    esac
done

# shellcheck source=/dev/null
. "$RADICE/impostazioni.conf"

titolo() { echo; echo "=== $* ==="; }
[ "$(id -u)" -eq 0 ] || { echo "Serve root." >&2; exit 1; }

PORTE=()
for ((i = 0; i < N_TERM; i++)); do PORTE+=( $((PORTA_BASE + i)) ); done

titolo "Riepilogo"
cat <<RIEP
dominio        : $DOMINIO
utente shell   : $UTENTE:$GRUPPO
terminali      : $N_TERM  (porte ${PORTE[0]}-${PORTE[-1]}, path /term0/ ... /term$((N_TERM-1))/)
webroot        : $WEBROOT
vhost          : $VHOST
cert server    : $SSL_CRT
CA client      : $CA_CRT
cert client in : $CERT_CLIENT_DIR
RIEP

# L'utente delle shell deve esistere: ttyd non lo crea e le unit fallirebbero
# a raffica con Restart=always.
id "$UTENTE" >/dev/null 2>&1 || { echo "ERRORE: l'utente '$UTENTE' non esiste su questo server." >&2; exit 1; }
[ "$UTENTE" = root ] && echo "ATTENZIONE: le shell girano come root. Un errore nell'mTLS diventa una root shell aperta."

# --- 1. pacchetti -------------------------------------------------------------
if [ "$SALTA_PACCHETTI" = no ]; then
    titolo "Pacchetti"
    # ttyd sta in EPEL, non nei repo base di Rocky/RHEL.
    rpm -q epel-release >/dev/null 2>&1 || dnf install -y epel-release
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

titolo "Certificato TLS del server"
"$RADICE/certs/cert-server.sh"

# --- 3. istanze ttyd ----------------------------------------------------------
titolo "Unit ttyd@"
sed -e "s|@UTENTE@|$UTENTE|g" -e "s|@GRUPPO@|$GRUPPO|g" \
    "$RADICE/conf/ttyd@.service.tmpl" > /etc/systemd/system/ttyd@.service
chmod 644 /etc/systemd/system/ttyd@.service
systemctl daemon-reload
for p in "${PORTE[@]}"; do
    systemctl enable "ttyd@$p" >/dev/null
    # restart e non start: un rilancio dopo un cambio di unit deve ripartire
    # con la configurazione nuova. Le sessioni tmux sopravvivono, sono
    # processi a se' stanti: al riavvio ttyd si riattacca con -A.
    systemctl restart "ttyd@$p"
done
sleep 1
for p in "${PORTE[@]}"; do
    printf '  ttyd@%s : %s\n' "$p" "$(systemctl is-active "ttyd@$p")"
done

# --- 4. dashboard -------------------------------------------------------------
titolo "Dashboard"
TERM_JS="["
for ((i = 0; i < N_TERM; i++)); do
    [ "$i" -gt 0 ] && TERM_JS+=", "
    TERM_JS+="{ id: $i, label: 'Term $i' }"
done
TERM_JS+="]"

install -d -m 755 "$WEBROOT"
[ -f "$WEBROOT/index.html" ] && cp -p "$WEBROOT/index.html" "$WEBROOT/index.html.bak-$(date +%Y%m%d%H%M%S)"
sed -e "s|@TITOLO@|$TITOLO|g" -e "s|@TERMINALS@|$TERM_JS|g" \
    "$RADICE/conf/index.html.tmpl" > "$WEBROOT/index.html"
chmod 644 "$WEBROOT/index.html"
echo "$WEBROOT/index.html: $N_TERM terminali"

# --- 5. vhost nginx -----------------------------------------------------------
titolo "nginx"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
for p in "${PORTE[@]}"; do
    echo "upstream ttyd_$p { server 127.0.0.1:$p; }" >> "$TMP/upstream"
done
for ((i = 0; i < N_TERM; i++)); do
    printf '    location /term%s/ { proxy_pass http://ttyd_%s/; }\n' "$i" "$((PORTA_BASE + i))" >> "$TMP/location"
done

# Il blocco multiriga si inserisce col trucco classico di sed: "r file"
# accoda il contenuto dopo la riga del segnaposto, "d" cancella il segnaposto.
sed -e "/@BLOCCHI_UPSTREAM@/r $TMP/upstream" -e "/@BLOCCHI_UPSTREAM@/d" \
    -e "/@BLOCCHI_LOCATION@/r $TMP/location" -e "/@BLOCCHI_LOCATION@/d" \
    -e "s|@DOMINIO@|$DOMINIO|g" -e "s|@SSL_CRT@|$SSL_CRT|g" -e "s|@SSL_KEY@|$SSL_KEY|g" \
    -e "s|@CA_CRT@|$CA_CRT|g" -e "s|@WEBROOT@|$WEBROOT|g" \
    "$RADICE/conf/nginx-terminali.conf.tmpl" > "$TMP/vhost.conf"

[ -f "$VHOST" ] && cp -p "$VHOST" "$VHOST.bak-$(date +%Y%m%d%H%M%S)"
install -m 644 -o root -g root "$TMP/vhost.conf" "$VHOST"

# --- 6. SELinux ---------------------------------------------------------------
# Con SELinux enforcing nginx NON puo' aprire connessioni di rete verso ttyd:
# il proxy_pass fallisce con 502 e in audit.log compare name_connect. Sulla
# macchina originale non si vedeva perche' e' in Permissive.
if command -v selinuxenabled >/dev/null && selinuxenabled; then
    titolo "SELinux ($(getenforce))"
    setsebool -P httpd_can_network_connect 1
    getsebool httpd_can_network_connect
    command -v restorecon >/dev/null && restorecon -R "$WEBROOT" || true
fi

# --- 7. firewall --------------------------------------------------------------
if systemctl is-active --quiet firewalld 2>/dev/null; then
    titolo "firewalld"
    firewall-cmd --permanent --add-service=https >/dev/null
    firewall-cmd --reload >/dev/null
    echo "443/tcp aperta"
fi

# --- 8. avvio nginx -----------------------------------------------------------
nginx -t
systemctl enable nginx >/dev/null
systemctl reload nginx 2>/dev/null || systemctl restart nginx
echo "nginx: $(systemctl is-active nginx)"

# --- 9. primo certificato client ---------------------------------------------
if [ -f "$CERT_CLIENT_DIR/$CLIENT_INIZIALE.p12" ]; then
    titolo "Certificato client"
    echo "gia' presente: $CERT_CLIENT_DIR/$CLIENT_INIZIALE.p12"
else
    titolo "Primo certificato client"
    echo "openssl chiedera' una password per il .p12: serve al browser in fase di import."
    "$RADICE/certs/emetti-client.sh" "$CLIENT_INIZIALE"
fi

# --- 10. verifica -------------------------------------------------------------
"$RADICE/verifica.sh" || true

cat <<FINE

=== Fatto ===

Il servizio e' raggiungibile SOLO con un certificato client: senza, ogni
richiesta riceve la pagina che spiega cosa manca. Per entrare:

  1. porta via il .p12         scp root@$DOMINIO:$CERT_CLIENT_DIR/$CLIENT_INIZIALE.p12 .
  2. importalo nel browser     (Chrome: Impostazioni > Privacy > Certificati > I tuoi certificati)
  3. apri                      https://$DOMINIO/

Un certificato in piu' per ogni dispositivo:

  certs/emetti-client.sh telefono-$UTENTE

FINE
