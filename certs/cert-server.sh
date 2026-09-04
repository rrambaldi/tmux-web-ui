#!/bin/bash
# Certificato TLS del server, quello che il browser verifica per la barra degli
# indirizzi. Autofirmato: il browser mostrera' un avviso da accettare una volta.
# Con un certificato vero (Let's Encrypt, CA aziendale) NON serve: si puntano
# SSL_CRT e SSL_KEY in impostazioni.conf ai file esistenti.
# Con --csr genera invece una richiesta da far firmare a una CA vera.
# [RR]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/comune.inc"
serveRoot

SOLO_CSR=no
[ "${1:-}" = "--csr" ] && SOLO_CSR=si

install -d -m 755 "$(dirname "$SSL_CRT")"
install -d -m 755 "$(dirname "$SSL_KEY")"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

SUBJ="/C=IT/ST=ITALY/L=MILANO/O=DIGITHERA/CN=$DOMINIO"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$TMP/srv.key"
openssl req -new -key "$TMP/srv.key" -sha256 -subj "$SUBJ" -out "$TMP/srv.csr"

if [ "$SOLO_CSR" = si ]; then
    install -m 600 -o root -g root "$TMP/srv.key" "$SSL_KEY"
    install -m 644 -o root -g root "$TMP/srv.csr" "$SSL_CRT.csr"
    echo "Chiave in $SSL_KEY e richiesta in $SSL_CRT.csr."
    echo "Fai firmare la CSR, poi metti il certificato in $SSL_CRT e ricarica nginx."
    exit 0
fi

if [ -f "$SSL_CRT" ] && [ -f "$SSL_KEY" ] && stessaCoppia "$SSL_CRT" "$SSL_KEY"; then
    echo "Certificato server gia' presente e coerente: $SSL_CRT"
    openssl x509 -in "$SSL_CRT" -noout -subject -ext subjectAltName -enddate
    exit 0
fi

# Autofirmato, non firmato dalla CA client: sono due ruoli diversi e tenerli
# separati evita che un certificato client possa spacciarsi per il server.
estServer "$DOMINIO" > "$TMP/srv.ext"
openssl x509 -req -in "$TMP/srv.csr" -signkey "$TMP/srv.key" -sha256 \
        -days 3650 -extfile "$TMP/srv.ext" -out "$TMP/srv.crt"

install -m 600 -o root -g root "$TMP/srv.key" "$SSL_KEY"
install -m 644 -o root -g root "$TMP/srv.crt" "$SSL_CRT"
echo "Certificato server autofirmato installato (SAN: DNS:$DOMINIO)."
openssl x509 -in "$SSL_CRT" -noout -subject -ext subjectAltName -enddate
