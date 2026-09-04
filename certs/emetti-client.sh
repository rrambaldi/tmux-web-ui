#!/bin/bash
# Emette un certificato client firmato dalla CA dei terminali e lo impacchetta
# in un .p12 da importare nel browser o nel telefono. Lascia anche la coppia in
# PEM, che serve a curl e ai client Linux.
#   ./emetti-client.sh <nome> [giorni]
# Un certificato per dispositivo, non uno per persona: cosi' si revoca il
# telefono perso senza toccare il resto. [RR]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/comune.inc"
serveRoot

CN=${1:?uso: $0 <nome> [giorni]}
GIORNI=${2:-$CLIENT_GIORNI}

[ -f "$CA_CRT" ] && [ -f "$CA_KEY" ] || { echo "CA assente: lancia prima crea-ca.sh" >&2; exit 1; }
openssl x509 -in "$CA_CRT" -noout -checkend 0 >/dev/null \
    || { echo "ERRORE: la CA e' scaduta, lancia prima rinnova-ca.sh" >&2; exit 1; }

install -d -m 700 "$CERT_CLIENT_DIR"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
estClient > "$TMP/client.ext"

openssl req -new -newkey rsa:2048 -nodes -keyout "$TMP/$CN.key" -sha256 \
        -subj "${CA_SUBJ%/CN=*}/CN=$CN" -out "$TMP/$CN.csr"

[ -f "$CA_SRL" ] || { echo 01 > "$CA_SRL"; chmod 600 "$CA_SRL"; }
openssl x509 -req -in "$TMP/$CN.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAserial "$CA_SRL" \
        -days "$GIORNI" -sha256 -extfile "$TMP/client.ext" -out "$TMP/$CN.crt"

openssl verify -CAfile "$CA_CRT" "$TMP/$CN.crt"

# -legacy (3DES/SHA1) perche' il default di OpenSSL 3 (AES-256 + PBKDF2) non
# viene importato dal keychain di iOS/macOS ne' da qualche Android datato.
# Se openssl e' 1.x l'opzione non esiste e si usa il formato di allora.
LEG=(-legacy)
openssl pkcs12 -help 2>&1 | grep -q -- '-legacy' || LEG=()
openssl pkcs12 -export "${LEG[@]}" \
        -inkey "$TMP/$CN.key" -in "$TMP/$CN.crt" -certfile "$CA_CRT" \
        -name "$CN" -out "$TMP/$CN.p12"

install -m 600 -o root -g root "$TMP/$CN.p12" "$CERT_CLIENT_DIR/$CN.p12"
install -m 600 -o root -g root "$TMP/$CN.crt" "$CERT_CLIENT_DIR/$CN.crt"
install -m 600 -o root -g root "$TMP/$CN.key" "$CERT_CLIENT_DIR/$CN.key"

echo
echo "Fatto:"
echo "  $CERT_CLIENT_DIR/$CN.p12   da importare nel browser o nel telefono"
echo "  $CERT_CLIENT_DIR/$CN.crt   + .key, in PEM, per curl e per i client Linux"
echo
# Il .p12 legacy usa RC2-40 per il sacco dei certificati: i browser e iOS lo
# leggono, OpenSSL 3 da riga di comando no, se non gli si ripassa -legacy. [RR]
echo "Per riguardarci dentro piu' avanti serve la stessa opzione:"
echo "  openssl pkcs12 -info -nokeys -legacy -in $CERT_CLIENT_DIR/$CN.p12"
echo
echo "Portalo via da qui, non servirlo dal web:"
echo "  scp root@$DOMINIO:$CERT_CLIENT_DIR/$CN.p12 ."
openssl x509 -in "$CERT_CLIENT_DIR/$CN.crt" -noout -subject -issuer -dates
