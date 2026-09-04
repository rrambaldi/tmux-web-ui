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
nginx -t >/dev/null 2>&1 && ok "configurazione valida" || no "nginx -t fallisce"
[ "$(systemctl is-active nginx)" = active ] && ok "nginx attivo" || no "nginx non attivo"

# --resolve evita di dipendere dal DNS; -k perche' il certificato del server
# puo' essere autofirmato: qui si sta verificando l'mTLS, non la catena TLS.
R=(--resolve "$DOMINIO:443:127.0.0.1" -sk --max-time 10)

echo "mTLS:"
SENZA=$(curl "${R[@]}" "https://$DOMINIO/" 2>/dev/null)
case "$SENZA" in
    *"Certificato client assente"*) ok "senza certificato: bloccato" ;;
    *"<title>"*)                    no "SENZA CERTIFICATO SI ENTRA: il controllo su \$ssl_client_verify non c'e' o non scatta" ;;
    *)                              info "senza certificato, risposta inattesa: $(echo "$SENZA" | head -1)" ;;
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

echo
[ "$ESITO" -eq 0 ] && echo "Tutto a posto." || echo "Ci sono problemi: vedi le righe KO."
exit "$ESITO"
