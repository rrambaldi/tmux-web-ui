#!/bin/bash
# Crea la CA che firma i certificati client dell'mTLS. E' l'unica autenticazione
# del servizio: chi ha un certificato firmato da questa CA ha una shell.
# Idempotente: se la CA c'e' gia' e la coppia e' coerente, non tocca niente.
# Per rifirmare una CA scaduta senza invalidare i client emessi: rinnova-ca.sh
# [RR]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/comune.inc"
serveRoot

if [ -f "$CA_CRT" ] && [ -f "$CA_KEY" ]; then
    if stessaCoppia "$CA_CRT" "$CA_KEY"; then
        echo "CA gia' presente: $CA_CRT"
        openssl x509 -in "$CA_CRT" -noout -subject -enddate
        openssl x509 -in "$CA_CRT" -noout -checkend 0 >/dev/null \
            || echo "ATTENZIONE: e' scaduta. Rifirmala con rinnova-ca.sh (i client restano validi)."
        exit 0
    fi
    echo "ERRORE: $CA_CRT e $CA_KEY esistono ma non sono la stessa coppia." >&2
    echo "Spostali a mano prima di rigenerare, o i certificati client emessi diventano carta straccia." >&2
    exit 1
fi

install -d -m 755 "$(dirname "$CA_CRT")"
install -d -m 700 "$(dirname "$CA_KEY")"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 4096 bit: la CA vive dieci anni e la firma la si fa una volta per client,
# quindi il costo non si sente da nessuna parte.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$TMP/ca.key"
estCa > "$TMP/ca.ext"
openssl req -new -key "$TMP/ca.key" -sha256 -subj "$CA_SUBJ" -out "$TMP/ca.csr"
openssl x509 -req -in "$TMP/ca.csr" -signkey "$TMP/ca.key" -sha256 \
        -days "$CA_GIORNI" -extfile "$TMP/ca.ext" -out "$TMP/ca.crt"

# Se non si autovalida, non validera' nemmeno i client: meglio accorgersene qui.
openssl verify -CAfile "$TMP/ca.crt" "$TMP/ca.crt" >/dev/null

install -m 600 -o root -g root "$TMP/ca.key" "$CA_KEY"
install -m 644 -o root -g root "$TMP/ca.crt" "$CA_CRT"
echo 01 > "$CA_SRL"; chmod 600 "$CA_SRL"

echo "CA creata:"
echo "  certificato : $CA_CRT   (lo legge nginx come ssl_client_certificate)"
echo "  chiave      : $CA_KEY   (0600, non deve uscire da questo server)"
openssl x509 -in "$CA_CRT" -noout -subject -enddate
