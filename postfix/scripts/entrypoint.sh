#!/bin/bash
# Hybrid Mail Router — container entrypoint
# Renders SQL map credentials, waits for MariaDB, configures Postfix, then execs CMD.
set -euo pipefail

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [entrypoint] $*"; }
die() { log "ERROR: $*"; exit 1; }

: "${MYSQL_HOST:=mariadb}"
: "${MYSQL_PORT:=3306}"
: "${MYSQL_DATABASE:=mailrouter}"
: "${MYSQL_USER:=postfix}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"
: "${POSTFIX_HOSTNAME:=mail-router.local}"
: "${POSTFIX_DOMAIN:=local}"
: "${POSTFIX_MYNETWORKS:=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}"
: "${POSTFIX_SMTPD_BANNER:=Hybrid Mail Router ESMTP}"
: "${POSTFIX_MESSAGE_SIZE_LIMIT:=52428800}"
: "${POSTFIX_TLS_ENABLED:=yes}"
: "${MYSQL_WAIT_TIMEOUT:=120}"

SQL_DIR=/etc/postfix/sql
CERT_DIR=/etc/postfix/certs
SPOOL=/var/spool/postfix

# ---------------------------------------------------------------------------
# Render MySQL map files from templates (credentials never baked into image)
# ---------------------------------------------------------------------------
render_sql_maps() {
  local template dest
  mkdir -p "$SQL_DIR"
  for template in "$SQL_DIR"/*.cf.template; do
    [[ -f "$template" ]] || continue
    dest="${template%.template}"
    sed \
      -e "s|__MYSQL_USER__|${MYSQL_USER}|g" \
      -e "s|__MYSQL_PASSWORD__|${MYSQL_PASSWORD}|g" \
      -e "s|__MYSQL_HOST__|${MYSQL_HOST}|g" \
      -e "s|__MYSQL_PORT__|${MYSQL_PORT}|g" \
      -e "s|__MYSQL_DATABASE__|${MYSQL_DATABASE}|g" \
      "$template" > "$dest"
    chown root:postfix "$dest"
    chmod 640 "$dest"
    log "Rendered $(basename "$dest")"
  done
}

# ---------------------------------------------------------------------------
# Wait for MariaDB to accept connections and routing table to exist
# ---------------------------------------------------------------------------
wait_for_mariadb() {
  local elapsed=0
  log "Waiting for MariaDB at ${MYSQL_HOST}:${MYSQL_PORT} (timeout ${MYSQL_WAIT_TIMEOUT}s)..."
  until mysqladmin ping \
      -h"$MYSQL_HOST" -P"$MYSQL_PORT" \
      -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
      --silent 2>/dev/null; do
    elapsed=$((elapsed + 2))
    if [[ $elapsed -ge $MYSQL_WAIT_TIMEOUT ]]; then
      die "MariaDB not reachable after ${MYSQL_WAIT_TIMEOUT}s"
    fi
    sleep 2
  done
  log "MariaDB is up"

  elapsed=0
  until mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
      "$MYSQL_DATABASE" -Nse "SELECT 1 FROM routing LIMIT 1" >/dev/null 2>&1; do
    elapsed=$((elapsed + 2))
    if [[ $elapsed -ge $MYSQL_WAIT_TIMEOUT ]]; then
      die "routing table not ready after ${MYSQL_WAIT_TIMEOUT}s"
    fi
    sleep 2
  done
  log "routing table is ready"
}

# ---------------------------------------------------------------------------
# TLS certificates (generate self-signed if missing and TLS enabled)
# ---------------------------------------------------------------------------
configure_tls() {
  mkdir -p "$CERT_DIR"
  if [[ "${POSTFIX_TLS_ENABLED}" != "yes" ]]; then
    postconf -e "smtpd_tls_security_level=none"
    postconf -e "smtp_tls_security_level=may"
    log "TLS disabled for smtpd"
    return
  fi

  if [[ ! -f "$CERT_DIR/fullchain.pem" || ! -f "$CERT_DIR/privkey.pem" ]]; then
    log "Generating self-signed TLS certificate for ${POSTFIX_HOSTNAME}..."
    openssl req -new -x509 -nodes -days 825 \
      -subj "/CN=${POSTFIX_HOSTNAME}/O=Hybrid Mail Router" \
      -newkey rsa:4096 \
      -keyout "$CERT_DIR/privkey.pem" \
      -out "$CERT_DIR/fullchain.pem" \
      >/dev/null 2>&1
    chmod 640 "$CERT_DIR/privkey.pem"
    chmod 644 "$CERT_DIR/fullchain.pem"
    chown root:postfix "$CERT_DIR/privkey.pem" "$CERT_DIR/fullchain.pem"
  fi

  postconf -e "smtpd_tls_cert_file=${CERT_DIR}/fullchain.pem"
  postconf -e "smtpd_tls_key_file=${CERT_DIR}/privkey.pem"
  postconf -e "smtpd_tls_security_level=may"
  postconf -e "smtp_tls_security_level=may"
  log "TLS configured (${CERT_DIR})"
}

# ---------------------------------------------------------------------------
# Apply runtime Postfix settings
# ---------------------------------------------------------------------------
configure_postfix() {
  postconf -e "myhostname=${POSTFIX_HOSTNAME}"
  postconf -e "mydomain=${POSTFIX_DOMAIN}"
  postconf -e "myorigin=\$mydomain"
  postconf -e "mynetworks=${POSTFIX_MYNETWORKS}"
  postconf -e "smtpd_banner=${POSTFIX_SMTPD_BANNER}"
  postconf -e "message_size_limit=${POSTFIX_MESSAGE_SIZE_LIMIT}"

  # Enforce pure-router posture every start
  postconf -e "mydestination="
  postconf -e "local_recipient_maps="
  postconf -e "local_transport=error:local delivery disabled — mail router only"
  postconf -e "mailbox_command="
  postconf -e "home_mailbox="
  postconf -e "virtual_mailbox_maps="
  postconf -e "virtual_mailbox_base="

  postconf -e "relay_domains=proxy:mysql:${SQL_DIR}/mysql-relay-domains.cf"
  postconf -e "relay_recipient_maps=proxy:mysql:${SQL_DIR}/mysql-relay-recipients.cf"
  postconf -e "transport_maps=proxy:mysql:${SQL_DIR}/mysql-transport.cf"
  postconf -e "maillog_file=/dev/stdout"

  # Ensure aliases exist
  [[ -f /etc/aliases ]] || echo "postmaster: root" > /etc/aliases
  newaliases 2>/dev/null || true

  # Fix spool permissions (volume may reset ownership)
  mkdir -p "$SPOOL" /var/log/mail
  postfix set-permissions 2>/dev/null || true
  chown -R postfix:postfix /var/log/mail || true

  log "Postfix configuration applied (hostname=${POSTFIX_HOSTNAME})"
}

# ---------------------------------------------------------------------------
# Validate maps can query MariaDB
# ---------------------------------------------------------------------------
validate_maps() {
  local sample
  sample=$(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    "$MYSQL_DATABASE" -Nse "SELECT email FROM routing LIMIT 1" 2>/dev/null || true)
  if [[ -n "$sample" ]]; then
    log "Sample route present: ${sample}"
    postmap -q "$sample" "mysql:${SQL_DIR}/mysql-transport.cf" \
      && log "transport_maps lookup OK for ${sample}" \
      || log "WARN: transport_maps lookup returned empty for ${sample}"
  else
    log "WARN: routing table is empty — all SMTP recipients will be rejected until rows are added"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Starting Hybrid Mail Router entrypoint"
render_sql_maps
wait_for_mariadb
configure_tls
configure_postfix
validate_maps

# Run any extra hooks
if [[ -d /docker-entrypoint.d ]]; then
  for f in /docker-entrypoint.d/*; do
    [[ -x "$f" ]] || continue
    log "Running hook $(basename "$f")"
    "$f"
  done
fi

log "Handing off to: $*"
exec "$@"
