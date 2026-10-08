#!/bin/bash
# Usuario de SOLO LECTURA para la herramienta de visualización (Metabase):
# solo ve los marts (modelo analítico), nunca raw ni staging.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${BI_READER_USER}') THEN
            CREATE ROLE ${BI_READER_USER} LOGIN PASSWORD '${BI_READER_PASSWORD}';
        END IF;
    END
    \$\$;
    GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${BI_READER_USER};
    GRANT USAGE ON SCHEMA marts TO ${BI_READER_USER};
    GRANT SELECT ON ALL TABLES IN SCHEMA marts TO ${BI_READER_USER};
    -- dbt recrea las tablas en cada corrida: el permiso debe aplicar a las futuras
    ALTER DEFAULT PRIVILEGES FOR ROLE ${POSTGRES_USER} IN SCHEMA marts
        GRANT SELECT ON TABLES TO ${BI_READER_USER};
EOSQL
