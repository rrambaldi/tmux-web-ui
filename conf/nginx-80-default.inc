
# PROTEGGI_80=default: questo blocco si prende il default server della 80, e
# quindi risponde a tutto quello che non ha un vhost con il proprio nome --
# l'indirizzo IP nudo, gli scanner, i Host: sconosciuti.
#
# 444 e' lo pseudo-codice di nginx per "chiudi la connessione senza
# rispondere": non si conferma nemmeno che qui ci sia un server.
#
# ATTENZIONE: e' l'unico pezzo di questa installazione che cambia il
# comportamento della macchina FUORI dai terminali. Su un server dedicato e'
# giusto cosi'; se sulla stessa macchina ci sono altri siti serviti in http
# senza server_name, questo li spegne. In quel caso: PROTEGGI_80=nome.
#
# Nessun server_name, di proposito: la configurazione di serie di nginx usa
# `server_name _` per il suo default server, e dichiararlo anche qui fa
# stampare "conflicting server name" a ogni `nginx -t` e a ogni reload. Un
# default server non ha bisogno di un nome: lo si sceglie per la porta.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 444;
}
