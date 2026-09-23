
    # --- profili per utente ---------------------------------------------------
    # La dashboard non conosce il proprio CN: glielo dice nginx. Sta dentro
    # questo server, quindi dietro l'mTLS come tutto il resto.
    location = @PREFISSO@/io {
        if ($ssl_client_verify != SUCCESS) { return 403; }
        default_type text/plain;
        return 200 "$cn_client\n";
    }

    # Un JSON per identita' con i nomi e l'ordine dei tab. GET per rileggerlo
    # cambiando browser, PUT per aggiornarlo: il PUT lo fa nginx stesso con
    # ngx_http_dav_module, che nel pacchetto di Rocky e' gia' compilato --
    # nessun backend, nessun processo in piu' da tenere in piedi.
    #
    # `if` con `return` e' uno dei due usi che la documentazione di nginx
    # considera sicuri, e serve qui: il controllo vale per ogni metodo.
    location @PREFISSO@/profili/ {
        # Il controllo dell'mTLS anche qui: col PREFISSO il server{} e' quello
        # del sito, che puo' lasciar entrare anche senza certificato.
        if ($ssl_client_verify != SUCCESS) { return 403; }
        if ($profilo_mio = 0) { return 403; }

        # Il file e' <DIR_PROFILI>/<cn>.json e il nome lo decide la map
        # qui sopra, non la richiesta. alias e non root: col PREFISSO l'URI
        # non finisce piu' come il percorso su disco.
        alias @DIR_PROFILI@/;

        dav_methods PUT DELETE;
        dav_access user:rw;
        # niente creazione di directory intermedie: l'unico percorso ammesso
        # e' /profili/<cn>.json, un livello solo
        create_full_put_path off;

        # un profilo sono due elenchi di dieci voci: 16k e' gia' abbondante,
        # e mette un tetto a cosa si puo' depositare qui
        client_max_body_size 16k;
        autoindex off;
        limit_except GET PUT DELETE { deny all; }
    }
