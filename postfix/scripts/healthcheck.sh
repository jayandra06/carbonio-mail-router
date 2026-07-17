#!/bin/bash
# Healthcheck: Postfix master running + SMTP port accepting connections + MariaDB maps readable
set -euo pipefail

# 1. Postfix process
postfix status >/dev/null 2>&1 || exit 1

# 2. SMTP listener
nc -z -w 3 127.0.0.1 25 >/dev/null 2>&1 || exit 1

# 3. Queue directory writable / spool healthy
[[ -d /var/spool/postfix/pid ]] || exit 1

# 4. SQL map configs present (credentials rendered)
[[ -f /etc/postfix/sql/mysql-transport.cf ]] || exit 1
[[ -f /etc/postfix/sql/mysql-relay-recipients.cf ]] || exit 1

# 5. Optional: MariaDB reachable (soft — network blips shouldn't kill container immediately)
if command -v mysqladmin >/dev/null 2>&1; then
  mysqladmin ping \
    -h"${MYSQL_HOST:-mariadb}" \
    -P"${MYSQL_PORT:-3306}" \
    -u"${MYSQL_USER:-postfix}" \
    -p"${MYSQL_PASSWORD:-}" \
    --silent >/dev/null 2>&1 || exit 1
fi

exit 0
