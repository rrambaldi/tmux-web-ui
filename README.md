# tmux-web: persistent browser terminals behind mutual TLS

Self-hosted web terminals that survive the browser: **N persistent `tmux` sessions**,
each exposed through [`ttyd`](https://github.com/tsl0922/ttyd) and reachable from a
tabbed dashboard — with **client-certificate authentication** as the only way in.

Close the tab, close the laptop, come back tomorrow: the shell is still where you left
it, still running.

*Documentazione in italiano: [README.it.md](README.it.md).*

```
browser  --https + client certificate-->  nginx :443
              (mTLS: no cert, no entry)       |
                                              |  /            -> tabbed dashboard (index.html)
                                              |  /term0/ ...  -> proxy_pass + websocket upgrade
                                              v
                                     ttyd :8700 ... :8709   (bound to 127.0.0.1 only)
                                              |
                                     tmux new-session -A -s term-87xx
                                              |
                                       bash -l  as an unprivileged user
```

Three parts, each with exactly one job:

- **tmux** keeps the session alive. It is what makes the terminal persistent.
- **ttyd** turns a TTY into a websocket. It listens on the loopback interface *only*:
  it has no authentication of its own and must never be reachable from outside.
- **nginx** does TLS, mutual TLS and proxying. It is the single entry point, and the
  only place where access is decided.

## Read this before you deploy it

This project puts **interactive shells on a public port**. The shells are writable and
run as a real user — with `sudo` rights, if that user has them. The whole security
model is one nginx directive:

```nginx
if ($ssl_client_verify != SUCCESS) { return 403; }
```

`ssl_verify_client` is deliberately set to `optional` rather than `on`, because `on`
answers `400 No required SSL certificate was sent`, which tells you nothing about what
is missing and wastes an afternoon. With `optional`, the connection is accepted and
then **rejected by the check above**, with a readable message.

**That check is the protection.** Remove it, or set `optional` without it, and every
terminal is a shell for anyone who reaches port 443, no credentials required. This is
not hypothetical: it happened on the original host, and it stayed that way for half a
day before anyone noticed.

## Install

```bash
# 1. say who and where
$EDITOR impostazioni.conf          # at minimum DOMINIO and UTENTE

# 2. install (as root)
sudo ./install.sh

# 3. take the client certificate with you and import it into your browser
scp root@SERVER:/root/certs-client/primo-accesso.p12 .
```

Tested on Rocky Linux 9. `ttyd` comes from EPEL; `nginx`, `tmux` and `openssl` from the
base repositories.

`install.sh` is **idempotent**: re-run it after editing a template in `conf/` or
changing `N_TERM` and it realigns everything, backing up whatever it overwrites.
`--salta-pacchetti` skips the `dnf` round on re-runs.

It finishes by calling `./verifica.sh`, which checks the things that actually matter:
that every instance is up, that **you cannot get in without a certificate**, and that
with one the dashboard and every `/termN/` return 200.

`N_TERM` is the single source of truth. The tab list in the HTML, the nginx `upstream`
and `location` blocks and the systemd instances are all generated from it, so the three
lists cannot drift apart.

### First access is the one awkward step

The service is protected by the client certificate, which means **the certificate
cannot be downloaded from the service itself**. Copy it out with `scp` and import it by
hand.

- **Chrome / Chromium / Edge** — Settings > Privacy and security > Security > Manage
  certificates > *Your certificates* > Import.
- **Firefox** — Settings > Privacy & Security > Certificates > View Certificates >
  *Your Certificates* > Import. Firefox keeps its own store, not the system one.
- **iOS / macOS** — the `.p12` installs as a profile; on iOS you then have to *enable*
  it under Settings > General > About > Certificate Trust Settings.
- **Android** — Settings > Security > Credentials > Install from storage, explicitly
  choosing "VPN & app certificate".

The `.p12` is exported in **legacy** format (3DES/SHA1) on purpose: the modern OpenSSL 3
default (AES-256 + PBKDF2) is rejected by the iOS/macOS keychain. The trade-off is that
you need the same flag to read it back, or OpenSSL 3 stops at `RC2-40-CBC: unsupported`:

```bash
openssl pkcs12 -info -nokeys -legacy -in /root/certs-client/primo-accesso.p12
```

### Devices come and go

```bash
sudo certs/emetti-client.sh phone-alice        # one certificate per device
sudo certs/emetti-client.sh laptop-alice 365   # lifetime in days
```

One certificate per **device**, not per person: a lost phone can then be written off
without touching anyone else. Revoking a single certificate would need a CRL — there
isn't one, and for a handful of devices the practical answer is to regenerate the CA
and reissue.

## Maintenance

| Task | How |
|---|---|
| Change the number of terminals | `N_TERM` in `impostazioni.conf`, then `./install.sh --salta-pacchetti` |
| CA expired | `sudo certs/rinnova-ca.sh` — re-signs with the **same** key and DN, so existing client certificates stay valid |
| Server certificate expired | regenerate with `certs/cert-server.sh`, or point `SSL_CRT`/`SSL_KEY` at a real one |
| See what is running | `systemctl status 'ttyd@*'`, `runuser -u USER -- tmux ls` |
| Reduce `N_TERM` | surplus instances keep running: `systemctl disable --now ttyd@8709` by hand |

## The dashboard

One `index.html` that loads each terminal in an `iframe`, one per tab. It is not a
generic frontend — every feature here exists because something was annoying.

- `Shift+←/→` moves through tabs in **visual order**; `Alt+0–9` jumps to a terminal's
  **id**, which never changes even after you reorder them.
- **Double-click** a tab to rename it. Names live in `localStorage`: they belong to that
  browser, not to the server.
- **Drag** tabs to reorder. Reordering moves the `<li>`, it does not recreate the
  iframe, so the session and its scrollback are untouched.
- `Ctrl+Alt+C` **freezes** the pane and dumps the visible screen into a `<pre>`, where
  selection and `Ctrl+C` always work. This exists because ttyd copies on every
  selection change via `document.execCommand('copy')`, which browsers silently refuse
  when the selection did not come from a short user gesture — the familiar "sometimes
  copy just doesn't work". `Ctrl+Ins` copies xterm's own selection without freezing.
- When the connection drops, the **tab name resets to its default**: if you typed
  `exit`, the tmux session is gone and `-A` will create a fresh one on reconnect, so the
  label would be describing something that no longer exists.
- ttyd's own messages ("Reconnecting…", "Press ⏎ to Reconnect") are forced to
  **sans-serif** through a `MutationObserver`. They are a `<div>` that ttyd appends
  inside the iframe with all styling inline, so neither the page's CSS nor a rule
  without `!important` would ever reach them.

Bootstrap is loaded from a CDN, so the **client** needs internet access (the server does
not). For an air-gapped setup, drop the two files into the webroot and fix the two URLs
in `conf/index.html.tmpl`.

## Gotchas, all of them found the hard way

**SELinux.** With SELinux **enforcing**, nginx cannot open network connections to ttyd:
`proxy_pass` fails with 502 and `audit.log` shows `name_connect`. `install.sh` sets
`httpd_can_network_connect=1`. The original host never hit this because it runs in
*permissive* mode — on an enforcing box it would have been the first thing to break.

**ttyd is read-only by default** since 1.7.0. Without `-W` you get a terminal you can
watch but not type into. It is in the unit file.

**`tmux new-session -A`** attaches if the session exists and creates it otherwise. That
is what makes the terminal persistent. The flip side: `exit` destroys the session for
good, and the next connection gets a new, empty one.

**Never put the `.p12` in the webroot.** It looks convenient for importing from a phone,
but it is the house key under the doormat. The scripts write it to `/root/certs-client`
with mode `0600` for a reason.

**Websocket timeouts.** The vhost sets `proxy_read_timeout 1d`. With the 60s default,
nginx closes an idle session and the terminal drops into reconnect. The original host
never noticed because tmux's status line refreshes every 15s and keeps the channel
warm — that is, it worked by accident.

**Clipboard.** The real fix would be a ttyd build that ships `@xterm/addon-clipboard`,
i.e. OSC 52, plus `tmux set -g set-clipboard on`. In the **1.7.7** bundle from EPEL,
xterm.js registers OSC handlers for 0, 1, 2, 4, 8, 10–12, 104, 110–112 and 1337 — **52
is not among them**, so the sequence would be consumed by nobody and is not worth
trying. Hence the freeze-and-copy workaround.

## Layout

```
impostazioni.conf              every setting, in one place
install.sh                     idempotent end-to-end installer
verifica.sh                    checks that a replica actually works, not just that it installed
conf/ttyd@.service.tmpl        systemd template unit: one instance per port
conf/nginx-terminali.conf.tmpl vhost: TLS, mTLS, websockets, /termN/ proxying
conf/index.html.tmpl           the tabbed dashboard
certs/comune.inc               shared x509 extensions and sanity checks
certs/crea-ca.sh               create the client CA (the service's authentication)
certs/cert-server.sh           server TLS certificate (self-signed, or --csr for a real CA)
certs/emetti-client.sh         issue a .p12 + PEM pair for one device
certs/rinnova-ca.sh            re-sign the CA without invalidating issued client certificates
```

Settings and script internals are named in Italian, as are the inline comments; the
documentation is available in both languages.

## Requirements

Rocky / RHEL / Alma 9 with EPEL (that is where `ttyd` lives), plus `nginx`, `tmux` and
`openssl`. On Debian/Ubuntu everything applies except three details: `apt install ttyd
tmux nginx`, the vhost goes in `/etc/nginx/sites-available` with a symlink in
`sites-enabled`, and there is no SELinux (AppArmor normally does not get in the way
here).

## License

MIT — see [LICENSE](LICENSE).
