
# --- profili per utente: chi sei ---------------------------------------------
# nginx non ha una variabile per il CN, solo il DN intero. Il DN arriva in
# formato RFC2253, che lo stampa al contrario, e se il certificato ha un
# emailAddress quello viene PRIMA del CN: il CN si cerca quindi in mezzo alla
# stringa, non in testa. Provato su entrambe le forme.
#
# Si accetta solo un CN che sia usabile come nome di file. Tutto il resto --
# CN assente, vuoto, troppo lungo, con caratteri strani -- diventa stringa
# vuota, e con l'identita' vuota non si legge e non si scrive niente. [RR]
map $ssl_client_s_dn $cn_client {
    default                                         "";
    "~(?:^|,)CN=(?<cn>[A-Za-z0-9._-]{1,64})(?:,|$)" $cn;
}

# Il file DEVE chiamarsi esattamente come l'identita': il backreference \1
# obbliga la seconda meta' del confronto a ripetere la prima. Cosi' non serve
# fidarsi del percorso che arriva dal browser, e nessuno puo' leggere ne'
# sovrascrivere il profilo di un altro. Il punto dentro un CN (r.rambaldi) e'
# trattato come carattere letterale, non come jolly: lo fa il backreference.
map "$cn_client:$uri" $profilo_mio {
    default                                   0;
    "~^([A-Za-z0-9._-]+):/profili/\1\.json$"  1;
}
