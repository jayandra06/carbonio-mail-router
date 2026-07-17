# Hybrid Mail Router

Production-ready **SMTP relay router** (no mailboxes). Postfix accepts mail, looks up each recipient in MariaDB, and relays to the configured backend (Zoho, Carbonio, etc.).

## Architecture

```
                    ┌─────────────────────────────────────────┐
  SMTP :25/:587 ──► │  Postfix (Ubuntu)                      │
                    │  • no local delivery                    │
                    │  • transport_maps → MariaDB             │
                    └───────────────┬─────────────────────────┘
                                    │ SELECT host,port FROM routing
                                    ▼
                    ┌─────────────────────────────────────────┐
                    │  MariaDB  +  Adminer (:8080 localhost)  │
                    │  table: routing                         │
                    └─────────────────────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
        smtp.zoho.in:587    172.20.0.10:25         other backends
```

| Recipient | Backend | Next hop |
|-----------|---------|----------|
| `sales@company.com` | zoho | `smtp.zoho.in:587` |
| `cto@company.com` | carbonio | `172.20.0.10:25` |

## Stack

| Service | Image / base | Role |
|---------|--------------|------|
| `postfix` | Ubuntu 24.04 + Postfix + postfix-mysql | SMTP router |
| `mariadb` | MariaDB 11.4 | Routing database |
| `adminer` | Adminer 4.8.1 | DB admin UI |

## Quick start

```bash
cp .env.example .env
# Edit .env — set MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD, POSTFIX_HOSTNAME

docker compose up -d --build
docker compose ps
docker compose logs -f postfix
```

Adminer: http://127.0.0.1:8080  
- System: **MySQL**  
- Server: **mariadb**  
- User / password / database: from `.env`

## Routing table

```sql
SELECT * FROM routing;
```

| Column | Purpose |
|--------|---------|
| `id` | Primary key |
| `email` | Full recipient (looked up on every RCPT TO) |
| `backend` | Label (`zoho`, `carbonio`, …) |
| `host` | SMTP host or IP |
| `port` | SMTP port |
| `enabled` | `1` = active (Postfix ignores `0`) |

Add a route:

```sql
INSERT INTO routing (email, backend, host, port, description)
VALUES ('hr@company.com', 'zoho', 'smtp.zoho.in', 587, 'HR on Zoho');
```

Postfix picks up new rows on the **next** lookup (no reload required).

> **Backend auth:** Carbonio/on-prem on port 25 usually accepts relay by IP (`POSTFIX_MYNETWORKS` on the backend). Providers like Zoho on **587** often require SMTP AUTH — either allowlist this router’s IP on the provider, relay to their inbound MX on port 25, or extend Postfix with `smtp_sasl_password_maps` for that host.

## How Postfix uses MariaDB

For every recipient:

1. **relay_domains** — domain part must appear in `routing`
2. **relay_recipient_maps** — full address must exist and `enabled=1`
3. **transport_maps** — returns `smtp:[host]:port`

Unknown recipients are rejected (`550`).

## Production notes

- **No mailboxes** — `mydestination` empty, local transport disabled
- **Persistent volumes** — MariaDB data, Postfix spool/queue, logs
- **TLS** — mount real certs in `./certs` as `fullchain.pem` + `privkey.pem`, or let entrypoint create self-signed
- **Adminer / MySQL ports** — bound to `127.0.0.1` by default
- **Trusted injectors** — put upstream MTAs in `POSTFIX_MYNETWORKS`
- **Healthchecks** — all three services
- **Logging** — Postfix → stdout + `/var/log/mail`; Docker `json-file` rotation

### Replace self-signed certs

```bash
cp /path/to/fullchain.pem ./certs/
cp /path/to/privkey.pem ./certs/
docker compose restart postfix
```

### Useful commands

```bash
# Queue
docker compose exec postfix mailq
docker compose exec postfix postqueue -p

# Test MariaDB transport lookup
docker compose exec postfix postmap -q sales@company.com mysql:/etc/postfix/sql/mysql-transport.cf

# Flush queue
docker compose exec postfix postqueue -f

# Follow logs
docker compose logs -f --tail=200 postfix mariadb
```

### SMTP smoke test (from a host in mynetworks)

```bash
swaks --to sales@company.com --from test@company.com \
  --server 127.0.0.1 --port 25 -tls
```

## Layout

```
├── docker-compose.yml
├── .env.example
├── certs/                 # TLS material (persistent bind mount)
├── logs/                  # optional host-visible supervisor logs
├── mariadb/init/          # schema + grants (first boot only)
└── postfix/
    ├── Dockerfile
    ├── config/            # main.cf, master.cf, SQL map templates
    └── scripts/           # entrypoint, healthcheck, supervisord, rsyslog
```

## Security checklist

- [ ] Change all passwords in `.env`
- [ ] Install CA-signed TLS certificates
- [ ] Restrict `POSTFIX_MYNETWORKS` to real upstreams
- [ ] Keep Adminer on localhost or behind SSO/VPN
- [ ] Do not expose MariaDB publicly
- [ ] Back up volume `mail-router-mariadb-data`
