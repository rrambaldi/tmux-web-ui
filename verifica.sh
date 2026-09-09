#!/bin/bash
# Controlla che una replica sia davvero funzionante, non solo installata:
# le istanze ttyd, le sessioni tmux, il rifiuto senza certificato client e
# l'accesso con certificato. Non modifica niente. [RR]
set -uo pipefail

RADICE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$RADICE/impostazioni.conf"

ESITO=0
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
no()   { printf '  \033[31mKO\033[0m   %s\n' "$*"; ESITO=1; }
info() { printf '  --   %s\n' "$*"; }

echo; echo "=== Verifica ($DOMINIO) ==="

echo "istanze ttyd e sessioni tmux:"
for ((i = 0; i < N_TERM; i++)); do
    P=$((PORTA_BASE + i))
    A=$(systemctl is-active "ttyd@$P" 2>/dev/null)
    [ "$A" = active ] && ok "ttyd@$P attiva" || no "ttyd@$P: $A"
done
# Le sessioni vanno cercate come l'utente delle shell: tmux ha un socket per utente.
SESS=$(runuser -u "$UTENTE" -- tmux ls 2>/dev/null | wc -l)
[ "$SESS" -ge "$N_TERM" ] && ok "$SESS sessioni tmux per $UTENTE" || info "sessioni tmux per $UTENTE: $SESS (nascono al primo collegamento)"

echo "nginx:"
# `nginx -t` da utente normale fallisce sui permessi (la chiave del server e'
# 0600 di root), non perche' la configurazione sia sbagliata: senza questa
# distinzione un controllo lanciato senza sudo urla al guasto.
if nginx -t >/dev/null 2>&1; then
    ok "configurazione valida"
elif [ "$(id -u)" -ne 0 ]; then
    info "nginx -t non verificabile da utente normale: rilancia con sudo"
else
    no "nginx -t fallisce"
    nginx -t 2>&1 | sed 's/^/       /'
fi
[ "$(systemctl is-active nginx)" = active ] && ok "nginx attivo" || no "nginx non attivo"

# --resolve evita di dipendere dal DNS; -k perche' il certificato del server
# puo' essere autofirmato: qui si sta verificando l'mTLS, non la catena TLS.
R=(--resolve "$DOMINIO:443:127.0.0.1" -sk --max-time 10)

echo "mTLS (ssl_verify_client $VERIFICA_CLIENT):"
# Il rifiuto ha due forme diverse a seconda della modalita': con 'on' e' nginx
# che chiude con 400 prima di guardare la configurazione del sito, con
# 'optional' e' la pagina di cortesia del vhost. Vanno bene entrambe: cio' che
# non deve mai succedere e' ricevere la dashboard.
#
# L'ORDINE dei rami conta, e i rifiuti vanno prima. La pagina d'errore di nginx
# e' HTML e ha un <title>: un ramo che cerchi genericamente "sembra una pagina"
# la prende per la dashboard e dichiara l'mTLS rotto su un server che invece
# funziona. Percio' l'unico marcatore ammesso per "sono entrato" e' qualcosa
# che ha solo la dashboard, cioe' `var TERMINALS`. [RR]
SENZA=$(curl "${R[@]}" "https://$DOMINIO/" 2>/dev/null)
CODICE=$(curl "${R[@]}" -o /dev/null -w '%{http_code}' "https://$DOMINIO/" 2>/dev/null)
case "$SENZA" in
    *"No required SSL certificate"*)
        ok "senza certificato: rifiutato da nginx con 400 (modo on)" ;;
    *"Certificato client assente"*)
        ok "senza certificato: bloccato dal controllo nel vhost (modo optional)" ;;
    *"var TERMINALS"*)
        no "SENZA CERTIFICATO SI ENTRA: mTLS non attivo" ;;
    *)
        if [ "$CODICE" = 400 ] || [ "$CODICE" = 403 ]; then
            ok "senza certificato: bloccato (HTTP $CODICE)"
        else
            no "senza certificato, risposta inattesa (HTTP $CODICE): $(echo "$SENZA" | head -1)"
        fi ;;
esac

CRT="$CERT_CLIENT_DIR/$CLIENT_INIZIALE.crt"
KEY="$CERT_CLIENT_DIR/$CLIENT_INIZIALE.key"
if [ -r "$CRT" ] && [ -r "$KEY" ]; then
    CON=$(curl "${R[@]}" --cert "$CRT" --key "$KEY" "https://$DOMINIO/" 2>/dev/null)
    case "$CON" in
        *"var TERMINALS"*) ok "con certificato: dashboard servita" ;;
        *)                 no "con certificato la dashboard non arriva: $(echo "$CON" | head -1)" ;;
    esac
    for ((i = 0; i < N_TERM; i++)); do
        C=$(curl "${R[@]}" -o /dev/null -w '%{http_code}' --cert "$CRT" --key "$KEY" "https://$DOMINIO/term$i/" 2>/dev/null)
        [ "$C" = 200 ] && ok "/term$i/ -> 200" || no "/term$i/ -> $C"
    done
else
    info "PEM del client non leggibili ($CRT): il test con certificato si salta"
    info "(gli .crt/.key sono 0600 sotto $CERT_CLIENT_DIR, questa parte va lanciata da root)"
fi

# --- esposizione in chiaro ----------------------------------------------------
# Il pezzo che l'mTLS non copre e che nessun controllo sulla 443 puo' vedere:
# il WEBROOT e' servito ANCHE dal default server della 80 della configurazione
# di serie di nginx, in chiaro e senza chiedere niente a nessuno. Il danno non
# e' la dashboard (i /term<n>/ non esistono su quella porta), e' qualunque file
# lasciato nel webroot. Un .p12 la' dentro e' l'unica autenticazione del
# servizio pubblicata su internet. [RR]
echo "esposizione in chiaro (porta 80, PROTEGGI_80=$PROTEGGI_80):"

CHIAVI=$(find "$WEBROOT" -maxdepth 3 -type f \
              \( -name '*.p12' -o -name '*.pfx' -o -name '*.key' -o -name '*.pem' \
                 -o -name '*.crt' -o -name '*.csr' \) 2>/dev/null)
if [ -n "$CHIAVI" ]; then
    no "CI SONO CHIAVI NEL WEBROOT: spostale fuori subito"
    echo "$CHIAVI" | while IFS= read -r f; do
        # Se sono davvero scaricabili lo si dice con l'URL in chiaro, che e' il
        # modo piu' rapido di far capire il problema a chi legge.
        C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1/${f#"$WEBROOT"/}" 2>/dev/null)
        if [ "$C" = 200 ]; then
            printf '       %s  -> scaricabile senza certificato (http, %s)\n' "$f" "$C"
        else
            printf '       %s  (http: %s)\n' "$f" "$C"
        fi
    done
else
    ok "nessuna chiave nel webroot"
fi

R80=(--resolve "$DOMINIO:80:127.0.0.1" -s --max-time 10)
# Per nome: e' il caso che PROTEGGI_80=nome deve coprire.
CODICE=$(curl "${R80[@]}" -o /dev/null -w '%{http_code}' "http://$DOMINIO/" 2>/dev/null)
CORPO=$(curl "${R80[@]}" "http://$DOMINIO/" 2>/dev/null)
case "$CORPO" in
    *"var TERMINALS"*)
        if [ "$PROTEGGI_80" = no ]; then
            info "http://$DOMINIO/ serve la dashboard in chiaro (scelta: PROTEGGI_80=no)"
        else
            no "http://$DOMINIO/ serve la dashboard in chiaro (HTTP $CODICE)"
        fi ;;
    *) case "$CODICE" in
           301|302) ok "http://$DOMINIO/ -> $CODICE verso https" ;;
           444|000) ok "http://$DOMINIO/ chiusa senza risposta" ;;
           *)       ok "http://$DOMINIO/ non serve la dashboard (HTTP $CODICE)" ;;
       esac ;;
esac

# Sull'IP nudo risponde il default server: lo copre solo PROTEGGI_80=default.
CORPO=$(curl -s --max-time 10 "http://127.0.0.1/" 2>/dev/null)
case "$CORPO" in
    *"var TERMINALS"*)
        if [ "$PROTEGGI_80" = default ]; then
            no "sull'IP nudo la dashboard si vede ancora: il default server non e' il nostro"
        else
            info "sull'IP nudo (http://127.0.0.1/) la dashboard si vede: la chiude PROTEGGI_80=default"
        fi ;;
    *)  ok "sull'IP nudo la dashboard non si vede" ;;
esac

echo
[ "$ESITO" -eq 0 ] && echo "Tutto a posto." || echo "Ci sono problemi: vedi le righe KO."
exit "$ESITO"
