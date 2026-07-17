#!/bin/bash
# Lightweight healthcheck — Postfix process only (DB checked at runtime by maps)
set -euo pipefail
postfix status >/dev/null 2>&1 || exit 1
nc -z -w 3 127.0.0.1 25 >/dev/null 2>&1 || exit 1
exit 0
