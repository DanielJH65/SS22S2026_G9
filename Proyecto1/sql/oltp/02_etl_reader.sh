#!/bin/bash
# Crea un usuario de SOLO LECTURA para que el ETL extraiga de la fuente
# (principio de mínimo privilegio: el pipeline nunca puede modificar el OLTP).
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE ${OLTP_USER} LOGIN PASSWORD '${OLTP_PASSWORD}';
    GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${OLTP_USER};
    GRANT USAGE ON SCHEMA oltp_sgfood TO ${OLTP_USER};
    GRANT SELECT ON ALL TABLES IN SCHEMA oltp_sgfood TO ${OLTP_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA oltp_sgfood GRANT SELECT ON TABLES TO ${OLTP_USER};
EOSQL
