# Hybrid Mail Router — Ubuntu + Postfix (no local mailboxes)
# Relays SMTP only; recipient routing via MariaDB lookups.

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="hybrid-mail-router"
LABEL org.opencontainers.image.description="Production Postfix SMTP router with MariaDB-backed recipient transport"
LABEL org.opencontainers.image.vendor="Hybrid Mail Router"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    POSTFIX_HOSTNAME=mail-router.local \
    POSTFIX_DOMAIN=local \
    MYSQL_HOST=mariadb \
    MYSQL_PORT=3306 \
    MYSQL_DATABASE=mailrouter \
    MYSQL_USER=postfix \
    MYSQL_PASSWORD=changeme \
    POSTFIX_MYNETWORKS="127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" \
    POSTFIX_SMTPD_BANNER="Hybrid Mail Router ESMTP" \
    POSTFIX_MESSAGE_SIZE_LIMIT=52428800 \
    POSTFIX_TLS_ENABLED=yes \
    POSTFIX_LOG_LEVEL=info

# Preseed Postfix for noninteractive install
RUN echo "postfix postfix/mailname string mail-router.local" | debconf-set-selections \
 && echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        postfix \
        postfix-mysql \
        mysql-client \
        ca-certificates \
        openssl \
        netcat-openbsd \
        curl \
        tzdata \
        supervisor \
        rsyslog \
        tini \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p \
        /etc/postfix/sql \
        /etc/postfix/certs \
        /var/spool/postfix \
        /var/log/mail \
        /var/log/supervisor \
        /docker-entrypoint.d \
 && postconf -e "mydestination=" \
 && postconf -e "local_recipient_maps=" \
 && postconf -e "local_transport=error:local delivery disabled — mail router only"

COPY config/main.cf /etc/postfix/main.cf
COPY config/master.cf /etc/postfix/master.cf
COPY config/sql/ /etc/postfix/sql/
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY scripts/rsyslog.conf /etc/rsyslog.d/50-postfix.conf
COPY scripts/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
 && chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
 && chmod 0644 /etc/postfix/main.cf /etc/postfix/master.cf \
 && chmod 0640 /etc/postfix/sql/*.cf.template \
 && chown -R root:root /etc/postfix \
 && printf 'postmaster: root\n' > /etc/aliases \
 && newaliases \
 && rm -f /etc/rsyslog.d/50-default.conf 2>/dev/null || true

EXPOSE 25 587

VOLUME ["/var/spool/postfix", "/var/log/mail", "/etc/postfix/certs"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
