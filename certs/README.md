# Place TLS material here (mounted at /etc/postfix/certs):
#   fullchain.pem  — certificate + chain
#   privkey.pem    — private key (mode 640, root:postfix inside container)
#
# If missing and POSTFIX_TLS_ENABLED=yes, entrypoint generates a self-signed cert.
