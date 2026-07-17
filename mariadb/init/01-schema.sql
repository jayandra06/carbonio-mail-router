-- =============================================================================
-- Hybrid Mail Router — MariaDB schema & seed data
-- Database: mailrouter
-- Postfix looks up `routing` for every SMTP recipient (domain, recipient, transport).
-- =============================================================================

SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS mailrouter
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE mailrouter;

-- Application user is created by docker-entrypoint via MYSQL_USER / MYSQL_PASSWORD.
-- Grant explicit privileges for Postfix lookups (idempotent).
-- Note: MariaDB container already creates MYSQL_USER with rights on MYSQL_DATABASE.
-- Extra grants kept for clarity when re-running against an existing volume.

CREATE TABLE IF NOT EXISTS routing (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email       VARCHAR(255)    NOT NULL COMMENT 'Full recipient address (case-insensitive match)',
  backend     VARCHAR(64)     NOT NULL COMMENT 'Logical backend label: zoho, carbonio, office365, ...',
  host        VARCHAR(255)    NOT NULL COMMENT 'SMTP host or IP of the backend',
  port        SMALLINT UNSIGNED NOT NULL DEFAULT 25 COMMENT 'SMTP port on the backend',
  enabled     TINYINT(1)      NOT NULL DEFAULT 1 COMMENT '1=active, 0=disabled (ignored by Postfix queries)',
  description VARCHAR(512)    NULL DEFAULT NULL,
  created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_routing_email (email),
  KEY idx_routing_backend (backend),
  KEY idx_routing_email_domain (email),
  KEY idx_routing_enabled_email (enabled, email)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Per-recipient SMTP routing for Hybrid Mail Router';

-- ---------------------------------------------------------------------------
-- Optional audit log of config changes (Adminer / ops)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS routing_audit (
  audit_id    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  routing_id  BIGINT UNSIGNED NULL,
  email       VARCHAR(255)    NOT NULL,
  action      ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  old_row     JSON NULL,
  new_row     JSON NULL,
  changed_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (audit_id),
  KEY idx_audit_email (email),
  KEY idx_audit_changed (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS trg_routing_ai;
DROP TRIGGER IF EXISTS trg_routing_au;
DROP TRIGGER IF EXISTS trg_routing_ad;

DELIMITER $$

CREATE TRIGGER trg_routing_ai
AFTER INSERT ON routing
FOR EACH ROW
BEGIN
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
END$$

CREATE TRIGGER trg_routing_au
AFTER UPDATE ON routing
FOR EACH ROW
BEGIN
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
END$$

CREATE TRIGGER trg_routing_ad
AFTER DELETE ON routing
FOR EACH ROW
BEGIN
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
END$$

DELIMITER ;

-- ---------------------------------------------------------------------------
-- Seed examples (replace with production routes via Adminer)
-- ---------------------------------------------------------------------------
INSERT INTO routing (email, backend, host, port, description) VALUES
  ('sales@company.com', 'zoho',     'smtp.zoho.in', 587, 'Zoho Mail India SMTP'),
  ('cto@company.com',   'carbonio', '172.20.0.10',  25,  'On-prem Carbonio MTA')
ON DUPLICATE KEY UPDATE
  backend     = VALUES(backend),
  host        = VALUES(host),
  port        = VALUES(port),
  description = VALUES(description),
  enabled     = 1;

-- ---------------------------------------------------------------------------
-- Views used by operators (Adminer-friendly)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_routes AS
SELECT
  id,
  email,
  SUBSTRING_INDEX(email, '@', -1) AS domain,
  backend,
  host,
  port,
  CONCAT('smtp:[', host, ']:', port) AS postfix_transport,
  description,
  updated_at
FROM routing
WHERE enabled = 1
ORDER BY domain, email;

-- Read-only hint for postfix user is handled by grants in 02-grants.sql
