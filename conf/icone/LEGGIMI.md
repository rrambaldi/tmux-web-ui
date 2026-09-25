# Icone della dashboard

Directory opzionale. `install.sh` copia nel `WEBROOT` tutto quello che trova
qui, poi genera i `<link>` corrispondenti dentro `index.html` — uno solo per
ogni file che esiste davvero, perche' un `<link>` verso un file assente e' un
404 a ogni caricamento della pagina.

I nomi riconosciuti sono quelli prodotti dai generatori di favicon:

| file                    | a cosa serve                            |
|-------------------------|-----------------------------------------|
| `apple-touch-icon.png`  | icona 180x180 per iOS / "aggiungi alla home" |
| `favicon-32x32.png`     | icona della scheda                      |
| `favicon-16x16.png`     | icona della scheda, schermi non HiDPI   |
| `favicon.svg`           | icona della scheda, cambia colore col tema chiaro o scuro del sistema |
| `site.webmanifest`      | nome e icone come app installabile      |
| `favicon.ico`           | nessun `<link>`: i browser lo chiedono da soli su `/favicon.ico` |

Qualunque altro file viene copiato nel `WEBROOT` ma non produce un `<link>`:
serve, per esempio, per gli `android-chrome-*.png` che vengono referenziati
dal `site.webmanifest` e non dall'HTML.

Tutti questi file li genera `design/esporta.py` dal marchio in
`design/marchio/` (vedi `design/ICONE-E-MARCHIO.md` per l'env conda che serve).

Questa directory e' vuota nel repo (i binari non ci stanno): se le icone sono
gia' nel `WEBROOT` di un server, i `<link>` vengono generati comunque e non
serve rimetterle qui.
