# Airflow 3 + dbt Core.
# La imagen oficial ya incluye psycopg 3, PyYAML y python-dotenv, que es todo lo
# que necesita src/sgfood_elt. dbt va en su propio virtualenv para que sus
# dependencias no choquen con las de Airflow.
FROM apache/airflow:3.3.2

USER root
COPY requirements-dbt.txt /tmp/requirements-dbt.txt
RUN python -m venv /opt/dbt-venv \
    && /opt/dbt-venv/bin/pip install --no-cache-dir -r /tmp/requirements-dbt.txt \
    && chown -R airflow:0 /opt/dbt-venv

USER airflow
