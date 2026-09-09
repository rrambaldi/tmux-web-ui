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
run as a real user — with `sudo` rights, if that user has them. Access control is a
single line, and the default is the strict one:

```nginx
ssl_verify_client on;          # VERIFICA_CLIENT in impostazioni.conf
```

With `on`, nginx demands the client certificate during the TLS handshake. A request
without one dies with `400 No required SSL certificate was sent` and never reaches a
`location` block at all.

`VERIFICA_CLIENT=optional` is the alternative, and it is a trade-off rather than simply
a weaker setting. nginx then accepts the connection and the vhost turns it away itself:

```nginx
if ($ssl_client_verify != SUCCESS) { return 403; }
```

which answers with a page naming *which* case it is — no certificate, an expired one, or
the wrong CA — instead of a blunt 400 that tells you nothing while you are locked out of
your own server. The price is that under `optional` **that check is the only
protection**: delete it and every terminal becomes a shell for anyone who reaches port
443, no credentials required. That is not hypothetical. It happened on the host this
project came from, and it stayed that way for half a day before anyone noticed.

The check is generated in both modes. Under `on` it never fires; it is there so that
switching to `optional` is one variable rather than a security review.

### Port 80 is not yours

mTLS guards port 443. It says nothing about port 80, and nginx ships with

```nginx
server { listen 80; server_name _; root /usr/share/nginx/html; }
```

which serves **the same webroot as the dashboard**, in the clear, asking nobody for
anything. The terminals themselves are not exposed there — `/term0/` and friends are
404 on that port, they only exist in the mTLS vhost — so what leaks is the dashboard
page and, far worse, *any file left in the webroot*.

`PROTEGGI_80` decides how far to push back:

| value | what it installs | covers |
|---|---|---|
| `nome` (default) | a port-80 server for `$DOMINIO` only, `301` to https | `http://your.host/…` |
| `default` | the above, plus `listen 80 default_server` answering `444` | also the bare IP and unknown `Host:` headers |
| `no` | nothing | nothing |

`default` is the right answer on a dedicated host. It is not the default because it is
the only part of this installation that changes the machine's behaviour *outside* the
terminals: on a shared server it would silence any other http site that has no
`server_name` of its own.

None of the three is the actual protection, though. The actual protection is that **no
key material ever lives in the webroot**, and `install.sh` refuses to run if it finds
any — see the corresponding gotcha below.

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

## Adopting an existing installation

The defaults in `impostazioni.conf` describe a fresh host. On a server that already
runs something like this, by hand, they will not match — and running `install.sh` with
mismatched defaults is worse than not running it:

- `DOMINIO` defaults to `hostname -f`, which is the machine's internal name. It is not
  necessarily the name people reach it by, nor the one in the certificate.
- `CA_CRT` points somewhere that does not exist yet. This is the one that would lock
  you out: a **new** CA gets created, nginx trusts only that one, and every client
  certificate already issued stops working. `crea-ca.sh` now refuses to run when only
  one half of the CA is where it expects it — the pair is either both there and
  matching, or nothing is there at all — but it can only catch the case where the
  existing file happens to sit at the configured path.
- `SSL_CRT` likewise: a real certificate under a different filename is not found, and
  a self-signed one is generated in its place.
- `VHOST` defaults to `terminali.conf`, so an existing vhost under another name is not
  replaced but *joined* — two servers on 443, and nginx keeps the first.

Write the real values into `impostazioni.locale.conf`, which is read **before** the
defaults and is not tracked by git:

```bash
cat > impostazioni.locale.conf <<'EOF'
: "${DOMINIO:=term.example.com}"
: "${UTENTE:=someone}"
: "${SSL_CRT:=/etc/nginx/ssl/wildcard.example.com.crt}"
: "${SSL_KEY:=/etc/nginx/ssl/wildcard.example.com.key}"
: "${CA_CRT:=/etc/ssl/certs/whatever-the-existing-ca-is-called.crt}"
: "${CA_KEY:=/etc/ssl/private/whatever-the-existing-ca-is-called.key}"
: "${VHOST:=/etc/nginx/conf.d/www.conf}"
EOF
```

Keep the `: "${VAR:=value}"` form: precedence is **environment > `impostazioni.locale.conf`
> `impostazioni.conf`**, and derived values (`SSL_CRT` from `DOMINIO`, and so on) are
computed after the local file is read, so they follow the real values rather than the
defaults.

Then look before you leap: `./verifica.sh` changes nothing and tells you what the
current state is, and `./install.sh` prints its full summary before touching anything.

## Maintenance

| Task | How |
|---|---|
| Change the number of terminals | `N_TERM` in `impostazioni.conf`, then `./install.sh --salta-pacchetti` |
| CA expired | `sudo certs/rinnova-ca.sh` — re-signs with the **same** key and DN, so existing client certificates stay valid |
| Server certificate expired | regenerate with `certs/cert-server.sh`, or point `SSL_CRT`/`SSL_KEY` at a real one |
| See what is running | `systemctl status 'ttyd@*'`, `runuser -u USER -- tmux ls` |
| Reduce `N_TERM` | surplus instances keep running: `systemctl disable --now ttyd@8709` by hand |
| Switch strict/diagnostic mTLS | `VERIFICA_CLIENT` (`on` / `optional`), then `./install.sh --salta-pacchetti` |
| Close port 80 as well | `PROTEGGI_80` (`nome` / `default` / `no`), then `./install.sh --salta-pacchetti` |
| Add favicons | drop the files in `conf/icone/`, then `./install.sh --salta-pacchetti` |
| Check a running installation | `sudo ./verifica.sh` — changes nothing, and covers the clear-text side too |

## The dashboard

One `index.html` that loads each terminal in an `iframe`, one per tab. It is not a
generic frontend — every feature here exists because something was annoying.

- `Shift+←/→` moves through tabs in **visual order**; `Alt+0–9` jumps to a terminal's
  **id**, which never changes even after you reorder them.
- **Double-click** a tab to rename it. Names live in `localStorage`: they belong to that
  browser, not to the server.
- **Drag** tabs to reorder. Reordering moves the `<li>`, it does not recreate the
  iframe, so the session and its scrollback are untouched.
- `Ctrl+Alt+C` (or the **Congela** button) stops the pane's output and dumps the
  visible screen into a `<pre>`, where mouse selection and `Ctrl+C` always work. This
  exists because ttyd copies on every selection change via
  `document.execCommand('copy')`, which browsers silently refuse when the selection
  did not come from a short user gesture — the familiar "sometimes copy just doesn't
  work". Freezing selects **nothing**: what to copy is your call. There is a *Copia
  tutto* button if you really do want the whole screen, and `Ctrl+Ins` copies xterm's
  own selection without freezing at all.
- A **key bar** at the bottom of the page for `Esc`, `Tab`, the four arrows and
  `PgUp`/`PgDn`. A phone's on-screen keyboard has none of those, and without them you
  cannot move around in `tmux` or `vi`, or complete a filename. Hold a button and it
  repeats, the way a real key does. It appears on its own where the pointer is a finger
  (`pointer: coarse`) and toggles with the **`⌨ Tasti`** button in the header, the choice
  remembered in `localStorage`. While a pane is frozen the keys go dead: they travel
  through `term.input()`, which honours `disableStdin` exactly as the real keyboard does.
- The page **adapts to the screen**. On a phone, desktop-sized Bootstrap tabs take three
  rows (~150px out of 700) straight off the terminal: below 480px they tighten and long
  labels are truncated, below 900px a little less. The same step lowers the terminal font
  (11px under 480, 12px under 900, otherwise whatever ttyd uses), because the font is
  what decides how many columns fit: on a 390px phone that is roughly fifty versus sixty,
  and you can see the difference in `htop` or a `diff`. The breakpoints live in exactly
  one place, `SCHERMI` in the JS — the CSS has no media queries of its own, it reacts to
  classes the JS puts on `body`.
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
but it is the house key under the doormat — and the doormat is on the street: the
webroot is served by nginx's stock port-80 server too, in the clear, with no client
certificate asked for. A `.p12` there is the service's *only* authentication published
on the internet, password-protected by a passphrase an attacker can grind offline at
their leisure. The scripts write it to `/root/certs-client` with mode `0600` for a
reason, and `install.sh` now refuses to run while any `.p12`, `.key`, `.pem`, `.crt`
or `.csr` sits under the webroot. `verifica.sh` checks the same thing and prints the
plain-http URL the file is reachable at, which tends to end the discussion.

**Favicons are generated from what exists.** The `<link>` tags in `index.html` are
emitted one per file actually present in the webroot (or in `conf/icone/`, from which
`install.sh` copies them). A `<link>` to a missing icon is a 404 on every page load,
and a hardcoded list is a list that goes stale — the binaries are not in the repo, but
a server that already has them keeps its icons across reinstalls.

**Websocket timeouts.** The vhost sets `proxy_read_timeout 1d`. With the 60s default,
nginx closes an idle session and the terminal drops into reconnect. The original host
never noticed because tmux's status line refreshes every 15s and keeps the channel
warm — that is, it worked by accident.

**Arrow keys have two forms.** With application cursor mode on (DECCKM, which `vi` and
full-screen interfaces set) an arrow is `ESC O A`; otherwise it is `ESC [ A`. The key bar
checks `term.modes.applicationCursorKeysMode` before deciding — always sending the second
form works in the shell and breaks elsewhere. `Esc` is `ESC`, `Tab` is `HT` (0x09),
`PgUp`/`PgDn` are `ESC [ 5~` and `ESC [ 6~`: the same sequences xterm.js itself emits for
those keys.

**Clipboard.** The real fix would be a ttyd build that ships `@xterm/addon-clipboard`,
i.e. OSC 52, plus `tmux set -g set-clipboard on`. In the **1.7.7** bundle from EPEL,
xterm.js registers OSC handlers for 0, 1, 2, 4, 8, 10–12, 104, 110–112 and 1337 — **52
is not among them**, so the sequence would be consumed by nobody and is not worth
trying. Hence the freeze-and-copy workaround.

## Layout

```
impostazioni.conf              every setting, in one place
impostazioni.locale.conf       optional, untracked: this server's real values (read first)
install.sh                     idempotent end-to-end installer
verifica.sh                    checks that a replica actually works, not just that it installed
conf/ttyd@.service.tmpl        systemd template unit: one instance per port
conf/nginx-terminali.conf.tmpl vhost: TLS, mTLS, websockets, /termN/ proxying
conf/nginx-80.conf.tmpl        port 80: redirect to https (see PROTEGGI_80)
conf/nginx-80-default.inc      extra block for PROTEGGI_80=default: takes the default server
conf/index.html.tmpl           the tabbed dashboard
conf/icone/                    optional favicons, copied to the webroot and linked if present
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
