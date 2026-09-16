# Host a Linger server

This is for the person running the server. Joining somebody else's server?
Use the [user guide](user-guide.md).

The server runs without a desktop. You control it through a terminal, usually
over SSH. You will install the desktop app on **your own computer** to make your
host account. Nothing on the [Releases page](https://github.com/itsMattGuenther/Linger/releases)
is a server installer.

## Before you start

- **A Linux computer reachable from the internet.** A VPS is easiest for a
  first try. For example, a small Ubuntu VPS from
  [DigitalOcean](https://www.digitalocean.com/products/droplets) works; 2 GiB
  of memory is a reasonable test starting point, not a measured minimum. You
  can use a computer at home, but you must also [set up your router](#hosting-at-home).
- **A domain name** you control, or [two free dynamic-DNS names](#using-free-names).
  You need two names because uploaded files must use a different address from
  the app. A bare IP address will not work in the installed app.
- **Docker Engine and the Compose plugin** on the server. On Ubuntu, use
  [Docker's Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/).
  Check that `docker compose version` works before continuing. If Docker says
  permission denied, put `sudo` before each `docker` command below.

On a VPS, connect from your computer with `ssh root@YOUR_VPS_IP`, replacing
`YOUR_VPS_IP` with its public IP. You can also use the provider's console; some
providers give you a username other than `root`. In the provider firewall,
allow **TCP 80 and 443 from anywhere** so Caddy can serve HTTPS. Allow **TCP 22
(SSH)** from your own IP if possible. If you turn on voice between different
networks, open the extra ports in [Voice](#voice-between-different-networks).

## 1. Point two names at the server

Find your VPS's **public IPv4 address** in its control panel. At your domain
registrar, add two A records. For `example.com`, Namecheap's **Advanced DNS →
Host Records** screen would look like this:

| Type | Host | Value | TTL |
|---|---|---|---|
| A Record | `linger` | your server's public IPv4 | Automatic |
| A Record | `cdn.linger` | the same public IPv4 | Automatic |

Those become `linger.example.com` and `cdn.linger.example.com`. Do not replace
your existing `@` or `www` records. Give DNS a few minutes to catch up. If
you're hosting at home, use your [home connection's public IPv4](#hosting-at-home)
instead.

## 2. Get the server files

Run these commands **on the server**, in a terminal. They make a `linger`
folder in your current directory and put two setup files inside it:

```bash
mkdir linger
cd linger
curl -fLO https://raw.githubusercontent.com/itsMattGuenther/Linger/main/deploy/compose.yaml
curl -fLO https://raw.githubusercontent.com/itsMattGuenther/Linger/main/deploy/Caddyfile
```

The Docker images download automatically later. The app on the Releases page
is only for people's computers.

## 3. Put your names in the files

Open the files with `nano compose.yaml` and `nano Caddyfile` (or another text
editor). In `compose.yaml`, change `LINGER_DOMAIN` from `linger.example.com`
to your main name. In `Caddyfile`, replace both example names with yours: the
first block is for Linger and the `cdn.` block is for files. Keep them as
**different names**. In `nano`, save with **Ctrl+O**, Enter, then **Ctrl+X**.

If your VPS has a 50 GiB disk, also uncomment `LINGER_POOL_BYTES` in
`compose.yaml` and set it to `10GB` for the test. The default 50 GB file pool
would leave too little space for the operating system and Docker.

## 4. Start the server

Still inside the `linger` folder, run:

```bash
docker compose run --rm --user root --entrypoint chown linger linger:linger /data
docker compose up -d
docker compose logs --tail=60 linger
```

The first command gives Linger permission to write its database in the `data`
folder. It also prevents the `unable to open database file` error seen on some
hosts. In the log, look for a **one-time setup link** like:

```text
https://linger.example.com/setup?token=…
```

Keep the entire link, including `?token=…`, private. Paste it into the Linger
desktop app in step 5, **not a browser**. Restarting Linger before you use the
link creates a new one and invalidates the old one. If you accidentally share
the link, restart Linger to replace it.

You may also see a warning that `LINGER_TURN_SECRET` is not set. That is about
the optional voice relay; it does not stop the server or text chat.

From **your own computer**, check the address before opening the app:
`curl -f https://linger.example.com/health` (replace the example name with
yours). If it does not return a short JSON response, use
[the connection checklist](#the-app-cannot-reach-the-server) first.

## 5. Make your host account

[Install and open the app](user-guide.md#installing-linger) on your own computer.
Paste the **whole setup link** into the *server or link* box and press
**continue**. Choose a server name, username, display name and password (at
least eight characters). The new account is the host account.

If the app says it cannot reach the server, check
[the connection steps below](#the-app-cannot-reach-the-server) before asking
for a new token. The desktop app does not start when you run Docker commands;
open it again the same way you installed it.

## 6. Invite people

In the left rail, next to the word *SERVER*, you have two small controls nobody
else sees: **manage** and **+ room**. Press **manage**, then **invites → make a
link**. You choose how many people it is good for and when it expires; the link
is copied for you the moment it is made. Send it however you normally talk to
your friends.

Before that, make a room: the empty screen offers **make the first room**, and
so does **+ room**. A room needs a short name for after the `#` and, if you
like, a topic.

An invite link is the only way to get an account. There is no public sign-up.
You can stop here; everything below is for later or for troubleshooting.

---

## Hosting at home

You can use a home computer instead of a VPS. It needs to stay on. From that
computer, `curl -4 https://api.ipify.org` shows the **public IPv4 address** for
your DNS records. Check that your router's WAN address matches it. If it does
not, you may be behind another router or carrier-grade NAT, and ordinary port
forwarding may not work.

In the router, reserve a **local IP address** for the computer and forward
**TCP 80 and 443** to that address. Allow those ports in the computer's firewall
too. This is the extra step a VPS avoids. DNS alone does not make a home server
reachable.

Anyone on the internet can then reach Linger through those ports. That does
not mean your computer will be instantly compromised, but keep the operating
system and Docker updated, and do not forward Docker's control port or Linger's
internal port 8420. After a short test, remove the router forwards and stop the
containers with `docker compose down`. Change or remove the two DNS records so
they no longer point to your home connection.

## Using free names

You do not have to buy a domain, but you still need **two names**. A free
dynamic-DNS provider such as DuckDNS can give you two, for example
`yourgroup.duckdns.org` and `yourgroupfiles.duckdns.org`. Set both to your
server's public IP on the provider's site (or use its IP updater).

In `compose.yaml`, set `LINGER_DOMAIN` to the first name and uncomment
`LINGER_MEDIA_DOMAIN` for the second. Put the same names in the two Caddyfile
blocks. Do not assume the provider lets you add `cdn.` in front of a free name.

---

## Running it day to day

Almost everything is done inside the app, not in a config file. The host
controls are behind **manage**, next to *SERVER* in the left rail.

- **Rooms** — host controls → *rooms*. Create, rename, set a topic, reorder,
  archive.
- **The server's name and accent color** — host controls → *server*. The name is
  what the rail shows and what an invite link tells a stranger.
- **Removing someone** — open their card in the roster and remove them. They
  disappear from everywhere.
- **Letting them back in** — host controls → *people*. Removals are reversible;
  that is the point.

Two things worth knowing. There is **no way to hand the host role to somebody
else**, on purpose. And there are no permissions to configure — if a group needs
that, it has outgrown what this app is for.

---

## Settings you might want to change

These go in `compose.yaml`, under `environment:`. Most people never touch them.
After a change, run `docker compose up -d` again.

| Setting | What it does | Default |
|---|---|---|
| `LINGER_POOL_BYTES` | Total storage the server will use. Write `250GB`, `500MB`, or a plain number. | `50GB` |
| `LINGER_FILE_EXPIRY_DAYS` | How long a file stays before it is deleted. `off` keeps everything forever. Starred files never expire. | `365` |
| `LINGER_MEDIA_DOMAIN` | The name files are served from. Set it if you are using two free names, or want something other than `cdn.` + your domain. It must be different from the main one. | `cdn.<your address>` |
| `LINGER_STORAGE` | `local` keeps files on the machine. `s3` keeps them in a cloud bucket. | `local` |
| `LINGER_DATA_DIR` | Where the database and files live inside the container. | `/data` |
| `LINGER_TURN_SECRET` | Turns on the voice relay (see below). Goes in `.env`, not here. | unset — no relay |
| `LINGER_TURN_URLS` | Where the relay is, if not `turn:<your address>:3478`. Comma-separated `turn:`/`stun:` addresses. | derived from your address |

One file can be up to 500 MB.

**Using a cloud bucket instead of the machine's disk.** Set `LINGER_STORAGE: s3`
and fill in the five `LINGER_S3_*` lines already written in `compose.yaml` as
comments. Cloudflare R2 is the one to pick, because it does not charge for data
going out. The server refuses to start if any of them are missing, so you will
know straight away.

## Voice between different networks

Two people on the same wifi can talk without any of this. Two people in two
houses usually cannot: home routers
hide the computers behind them, and somebody has to introduce the two — that is
a *relay*, and it is the third container in `compose.yaml`. It is yours, on your
machine; what passes through it is scrambled sound it cannot listen to.

1. Download the optional file, then copy it next to `compose.yaml`:

   ```bash
   curl -fLO https://raw.githubusercontent.com/itsMattGuenther/Linger/main/deploy/.env.example
   cp .env.example .env
   ```
2. Put a long random secret in it: `openssl rand -hex 32` prints one. This one
   value is shared between Linger and the relay and is the relay's only lock,
   so make it long and do not reuse it anywhere.
3. In `compose.yaml`, change `--realm=linger.example.com` to your address.
4. Open two more things on your router or firewall: port **3478**, both TCP and
   UDP, and UDP ports **49160 to 49200**. (If the machine is behind a home
   router rather than on a public address, also uncomment `--external-ip` and
   put your public IP there.)
5. Start with the relay switched on:
   ```bash
   docker compose --profile voice up -d
   ```
   Without `--profile voice` the relay does not start, which is fine for a
   server that does not want one.

The server tells you at startup if it has no relay. Voice still works then,
between machines on one network.

---

## Backups

The whole server is the `data` folder next to your `compose.yaml`. It holds
`linger.db` (every message) and `objects/` (every uploaded file).

Copy it while the server is stopped, so you never catch the database mid-write:

```bash
docker compose stop linger
tar czf linger-backup-$(date +%F).tar.gz data
docker compose start linger
```

That is a few seconds of downtime. Put it in a scheduled job and keep the copies
somewhere that is not this machine.

To restore: stop everything, put the `data` folder back, start again.

(If you moved files to a cloud bucket, `data/objects/` is empty and the bucket
is the other half of your backup.)

## Exports (and what they do to your disk)

Any member can ask the server for a zip of everything on it — every message and
every file. This is deliberate and you cannot turn it off: it is the promise
that nobody is locked in, including when the person locking them in would be
you.

Two things keep it from being a problem. A member can only ask **once an hour**,
and each member has **one** archive at a time — asking again deletes the
previous one. So the most it can cost you is one extra copy of your server per
member, and in practice far less.

Those archives live alongside your uploaded files and are not counted in the
storage figure members see. If disk space is tight, that is worth knowing.

**An export is not your backup.** It is a readable copy for a person. Your
backup is the `data` folder, above.

## Updating the server

```bash
docker compose pull
docker compose up -d
```

Nothing updates itself. You decide when.

## Somebody forgot their password

The server has one maintenance command. Stop it first — the database allows one
writer at a time.

```bash
docker compose stop linger
docker compose run --rm linger reset-password their-username
docker compose start linger
```

It prints a new password. Send it to them; they can change it in the app under
*settings → password*.

---

## When something is wrong

**Start here:** `docker compose logs linger` and `docker compose logs caddy`.

### The app cannot reach the server

Check that both DNS records point to the server's *current* public IP, then
try `curl -f https://linger.example.com/health` with your own name substituted.
If that fails, check `docker compose ps` and `docker compose logs caddy`.
Caddy needs inbound access for its certificate checks, and the app needs HTTPS
on TCP 443. Allow TCP 80 and 443. On a VPS check the provider and machine
firewalls; at home check router forwarding too. A valid setup token cannot fix
a connection failure.

### Other problems

- **`unable to open database file` repeats in Linger's log.** The `data`
  folder is not writable by the container. Run the permission command in
  step 4, then `docker compose up -d` again. It does not delete the database.
- **Voice connects on the same wifi but not between houses.** The relay is not
  running, or its ports are not open. `docker compose ps` should list `coturn`;
  if it does not, you started without `--profile voice`. If it is running,
  check port 3478 (TCP and UDP) and UDP 49160–49200 reach the machine, and that
  `.env` holds the same secret Linger was started with.
- **Chat works but uploads fail.** The `cdn.` record is missing, or the second
  block of the Caddyfile still says `linger.example.com`.
- **`docker compose pull` says `unauthorized`.** The prebuilt image is not
  available to you. Clone the repository and build it yourself:
  `docker build -f deploy/Dockerfile -t ghcr.io/matthewguenther/linger:latest .`
- **The setup link does not work.** It works once. If you already made an
  account, it is gone for good — that is deliberate. If no account was made
  but the link was exposed or lost, `docker compose restart linger` prints a
  new one and invalidates the old one.
- **The startup log warns that `LINGER_DOMAIN` is not set.** Then your friends
  cannot connect, whatever else looks fine. The app only talks to `https`
  addresses. Go back to [Before you start](#before-you-start).

---

## What you are taking on

Say this out loud to the people you invite, because it is true:

> **Whoever runs the server can read everything on it.** Messages and files are
> encrypted while they travel and sit on an encrypted disk if you set one up,
> but there is no end-to-end encryption. Your friends are trusting you, not the
> software.

Linger has no telemetry, analytics, or crash reporting. Nobody is counting
your users.
