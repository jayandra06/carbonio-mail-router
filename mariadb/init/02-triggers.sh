#!/bin/bash
# Create audit triggers (DELIMITER cannot be used reliably in docker *.sql init).
set -euo pipefail

echo "[triggers] Creating routing audit triggers"

mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" mailrouter <<'EOSQL'
DROP TRIGGER IF EXISTS trg_routing_ai;
DROP TRIGGER IF EXISTS trg_routing_au;
DROP TRIGGER IF EXISTS trg_routing_ad;

CREATE TRIGGER trg_routing_ai
AFTER INSERT ON routing
FOR EACH ROW
INSERT INTO routing_audit (routing_id, email, action, new_row)
VALUES (
  NEW.id,
  NEW.email,
  'INSERT',
  JSON_OBJECT(
    'email', NEW.email,
    'backend', NEW.backend,
    'host', NEW.host,
    'port', NEW.port,
    'enabled', NEW.enabled
  )
);

CREATE TRIGGER trg_routing_au
AFTER UPDATE ON routing
FOR EACH ROW
INSERT INTO routing_audit (routing_id, email, action, old_row, new_row)
VALUES (
  NEW.id,
  NEW.email,
  'UPDATE',
  JSON_OBJECT(
    'email', OLD.email,
    'backend', OLD.backend,
    'host', OLD.host,
    'port', OLD.port,
    'enabled', OLD.enabled
  ),
  JSON_OBJECT(
    'email', NEW.email,
    'backend', NEW.backend,
    'host', NEW.host,
    'port', NEW.port,
    'enabled', NEW.enabled
  )
);

CREATE TRIGGER trg_routing_ad
AFTER DELETE ON routing
FOR EACH ROW
INSERT INTO routing_audit (routing_id, email, action, old_row)
VALUES (
  OLD.id,
  OLD.email,
  'DELETE',
  JSON_OBJECT(
    'email', OLD.email,
    'backend', OLD.backend,
    'host', OLD.host,
    'port', OLD.port,
    'enabled', OLD.enabled
  )
);
EOSQL

echo "[triggers] Done."
