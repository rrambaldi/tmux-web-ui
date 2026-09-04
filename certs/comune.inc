# Pezzi condivisi dagli script dei certificati. Si include con:
#   . "$(dirname "${BASH_SOURCE[0]}")/comune.inc"
# [RR]

RADICE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$RADICE/impostazioni.conf"

serveRoot() {
    [ "$(id -u)" -eq 0 ] || { echo "Serve root: le chiavi stanno sotto /etc/ssl/private." >&2; exit 1; }
}

# Estensioni di una CA: puo' firmare altri certificati, e solo quello.
estCa() {
    cat <<'EXT'
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
basicConstraints       = critical,CA:TRUE
keyUsage               = critical,keyCertSign,cRLSign
EXT
}

# Estensioni di un certificato client: clientAuth, non serverAuth. Senza
# extendedKeyUsage qualche browser lo scarta e non lo propone all'utente.
estClient() {
    cat <<'EXT'
basicConstraints       = CA:FALSE
keyUsage               = critical,digitalSignature,keyEncipherment
extendedKeyUsage       = clientAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid,issuer
EXT
}

# Estensioni del certificato del server. Il CN non basta piu' a nessun browser
# dal 2017: quello che si guarda e' il SAN, che va passato qui.
estServer() {
    cat <<EXT
basicConstraints       = CA:FALSE
keyUsage               = critical,digitalSignature,keyEncipherment
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
subjectAltName         = DNS:$1
EXT
}

# La chiave corrisponde davvero a quel certificato? Si confrontano le chiavi
# PUBBLICHE in PEM: "openssl x509 -pubkey" e "openssl pkey -pubout" emettono lo
# stesso SPKI byte per byte, con RSA e con EC. Non si usa il modulo: -modulus
# esiste solo in "openssl rsa" (in "openssl pkey" no) e vale solo per RSA.
# Il confronto degli md5 sarebbe peggio: se entrambi i comandi falliscono, i due
# md5 dell'input vuoto coincidono e una coppia sbagliata passerebbe. [RR]
stessaCoppia() {
    local a b
    a=$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null) || return 1
    b=$(openssl pkey -in "$2" -pubout 2>/dev/null) || return 1
    [ -n "$a" ] && [ "$a" = "$b" ]
}
