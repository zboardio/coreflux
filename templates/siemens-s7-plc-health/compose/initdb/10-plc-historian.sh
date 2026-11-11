#!/bin/bash
# The historian, on the database's FIRST start only (an empty data volume): the template's SQL in its order, then the
# two roles with the passwords from the container's environment. The image's entrypoint sources this file.
# Every SQL file is idempotent: to apply a newer version later, run the same psql lines against the running database.

for f in schema.sql plc_fleet.sql s7_1500_ob_fault.sql s7_event_text.sql; do
    psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "$POSTGRES_DB" -f "/plc-sql/$f" || exit 1
done
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "$POSTGRES_DB" \
     -v db="$POSTGRES_DB" -v writer_password="$UNS_WRITER_PASSWORD" -v reader_password="$GRAFANA_READER_PASSWORD" \
     -f /plc-sql/role.sql || exit 1
