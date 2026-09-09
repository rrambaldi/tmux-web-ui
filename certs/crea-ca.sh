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

# Uno dei due c'e' e l'altro no. Tipico di un'installazione adottata, dove la
# CA esiste con un nome suo e CA_KEY punta ancora al default: senza questo
# controllo si scendeva a generare una CA nuova, e il `install ... "$CA_CRT"`
# in fondo sovrascriveva la CA vera. nginx si sarebbe fidato solo di quella
# nuova e OGNI certificato client emesso finora avrebbe smesso di funzionare.
# Si crea una CA solo quando non c'e' niente da rovinare. [RR]
if [ -f "$CA_CRT" ] || [ -f "$CA_KEY" ]; then
    echo "ERRORE: della CA c'e' solo un pezzo, e non si sovrascrive niente al buio." >&2
    [ -f "$CA_CRT" ] && echo "  certificato: $CA_CRT (c'e')"   >&2 || echo "  certificato: $CA_CRT (manca)" >&2
    [ -f "$CA_KEY" ] && echo "  chiave     : $CA_KEY (c'e')"   >&2 || echo "  chiave     : $CA_KEY (manca)" >&2
    cat >&2 <<MOTIVO

Se questa e' un'installazione che esisteva gia', il pezzo che "manca" ha un
nome diverso: mettilo in impostazioni.locale.conf (CA_CRT / CA_KEY) e rilancia.
Generare una CA nuova qui sovrascriverebbe quella vera, e tutti i certificati
client emessi finora smetterebbero di funzionare.
MOTIVO
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
