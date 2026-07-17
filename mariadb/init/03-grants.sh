#!/bin/bash
# Grant SELECT on routing objects to the Postfix lookup user (MYSQL_USER).
set -euo pipefail

: "${MYSQL_USER:=postfix}"
: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD required}"

echo "[grants] Ensuring SELECT for '${MYSQL_USER}' on mailrouter.routing"

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOSQL
GRANT SELECT ON mailrouter.routing TO '${MYSQL_USER}'@'%';
GRANT SELECT ON mailrouter.v_active_routes TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL

echo "[grants] Done."
