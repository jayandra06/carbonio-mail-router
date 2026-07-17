-- =============================================================================
-- Hybrid Mail Router — MariaDB schema & seed data
-- Keep this file free of DELIMITER / stored programs (Docker init is fragile).
-- Triggers are created in 02-triggers.sh instead.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS mailrouter
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE mailrouter;

CREATE TABLE IF NOT EXISTS routing (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email       VARCHAR(255)    NOT NULL COMMENT 'Full recipient address (case-insensitive match)',
  backend     VARCHAR(64)     NOT NULL COMMENT 'Logical backend label: zoho, carbonio, office365, ...',
  host        VARCHAR(255)    NOT NULL COMMENT 'SMTP host or IP of the backend',
  port        SMALLINT UNSIGNED NOT NULL DEFAULT 25 COMMENT 'SMTP port on the backend',
  enabled     TINYINT(1)      NOT NULL DEFAULT 1 COMMENT '1=active, 0=disabled',
  description VARCHAR(512)    NULL DEFAULT NULL,
  created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_routing_email (email),
  KEY idx_routing_backend (backend),
  KEY idx_routing_enabled_email (enabled, email)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Per-recipient SMTP routing for Hybrid Mail Router';

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

INSERT INTO routing (email, backend, host, port, description) VALUES
  ('sales@company.com', 'zoho',     'smtp.zoho.in', 587, 'Zoho Mail India SMTP'),
  ('cto@company.com',   'carbonio', '172.20.0.10',  25,  'On-prem Carbonio MTA')
ON DUPLICATE KEY UPDATE
  backend     = VALUES(backend),
  host        = VALUES(host),
  port        = VALUES(port),
  description = VALUES(description),
  enabled     = 1;

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
