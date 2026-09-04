#!/bin/bash
# Rifirma il certificato della CA usando la STESSA chiave e lo STESSO subject
# DN, cosi' i certificati client gia' emessi continuano a validare: un client
# valida contro issuer + Authority Key Identifier, non contro il file.
# Non installa niente finche' non ha verificato che subject e Subject Key
# Identifier del nuovo certificato coincidano con quelli del vecchio. [RR]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/comune.inc"
serveRoot

[ -f "$CA_CRT" ] && [ -f "$CA_KEY" ] || { echo "CA assente: qui si rinnova, non si crea. Usa crea-ca.sh" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- 1. fotografia dell'attuale, per il confronto finale
SUBJ_OLD=$(openssl x509 -in "$CA_CRT" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
SKID_OLD=$(openssl x509 -in "$CA_CRT" -noout -ext subjectKeyIdentifier | tail -1 | tr -d ' \t')
echo "CA attuale : $SUBJ_OLD"
echo "SKID       : $SKID_OLD"
echo "scadenza   : $(openssl x509 -in "$CA_CRT" -noout -enddate | sed 's/^notAfter=//')"

# --- 2. la chiave e' davvero quella di questo certificato?
stessaCoppia "$CA_CRT" "$CA_KEY" || { echo "ERRORE: la chiave non corrisponde al certificato." >&2; exit 1; }

# --- 3. rifirma, subject ed estensioni identici all'originale
SUBJ=$(openssl x509 -in "$CA_CRT" -noout -subject | sed 's/^subject=//; s/, /\//g; s/^ *//')
case "$SUBJ" in /*) ;; *) SUBJ="/$SUBJ";; esac
SUBJ=$(echo "$SUBJ" | sed 's/ = /=/g')
estCa > "$TMP/ca.ext"
openssl req -new -key "$CA_KEY" -sha256 -subj "$SUBJ" -out "$TMP/ca.csr"
openssl x509 -req -in "$TMP/ca.csr" -signkey "$CA_KEY" -sha256 \
        -days "$CA_GIORNI" -extfile "$TMP/ca.ext" -out "$TMP/ca.crt"

# --- 4. il nuovo e' equivalente al vecchio?
SUBJ_NEW=$(openssl x509 -in "$TMP/ca.crt" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
SKID_NEW=$(openssl x509 -in "$TMP/ca.crt" -noout -ext subjectKeyIdentifier | tail -1 | tr -d ' \t')
echo
echo "CA nuova   : $SUBJ_NEW"
echo "SKID       : $SKID_NEW"
echo "scadenza   : $(openssl x509 -in "$TMP/ca.crt" -noout -enddate | sed 's/^notAfter=//')"
echo
[ "$SUBJ_NEW" = "$SUBJ_OLD" ] || { echo "ERRORE: subject DN diverso, i client esistenti non validerebbero piu'." >&2; exit 1; }
[ "$SKID_NEW" = "$SKID_OLD" ] || { echo "ERRORE: Subject Key Identifier diverso." >&2; exit 1; }
openssl verify -CAfile "$TMP/ca.crt" "$TMP/ca.crt" >/dev/null || { echo "ERRORE: il nuovo certificato non si autovalida." >&2; exit 1; }
echo "OK: subject e SKID coincidono, i certificati client esistenti restano validi."

# --- 5. installazione con backup
BK="$CA_CRT.bak-$(date +%Y%m%d%H%M%S)"
cp -p "$CA_CRT" "$BK"
install -m 644 -o root -g root "$TMP/ca.crt" "$CA_CRT"
echo "Installato. Backup del precedente in $BK"

# --- 6. nginx, con marcia indietro se la configurazione non regge
if nginx -t; then
    systemctl reload nginx && echo "nginx ricaricato."
else
    echo "ATTENZIONE: nginx -t fallito, ripristino il backup." >&2
    install -m 644 -o root -g root "$BK" "$CA_CRT"
    exit 1
fi
