"""
### SG-Food · Pipeline ELT diario

Orquesta el flujo completo **fuentes → raw → dbt (staging → intermediate → marts) → validaciones**.

| Etapa | Qué hace |
|---|---|
| `preparar_lote` / `verificar_fuentes` | Genera el id del lote y comprueba que OLTP, CSV y DW estén disponibles |
| `extraccion_carga` | Python carga en paralelo cada tabla OLTP y cada CSV a `raw` (una tarea por tabla) |
| `decidir_inyeccion` | Solo si el parámetro `inyectar_casos_calidad` = true inserta los casos inválidos de prueba |
| `transformacion_dbt` | `deps` → `source freshness` → `build staging` (pruebas de entrada) → `build marts` → `docs` |
| `validaciones_sql` | Ejecuta `sql/validation/*.sql` y la reconciliación OLTP → raw; guarda todo en `audit.validation_result` |
| `resumen_ejecucion` | Siempre corre; consolida el resultado en `audit.pipeline_run` y marca la corrida como fallida si algo falló |

Reintentos con backoff exponencial, timeout por tarea y alerta en el log ante cualquier fallo.
"""
from __future__ import annotations

import logging
import os
import uuid
from datetime import timedelta

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.empty import EmptyOperator
from airflow.sdk import Param, TriggerRule, dag, get_current_context, task, task_group
from airflow.sdk.exceptions import AirflowFailException

log = logging.getLogger("sgfood_elt.dag")

DBT_BIN = os.environ.get("DBT_BIN", "/opt/dbt-venv/bin/dbt")
DBT_DIR = os.environ.get("DBT_PROJECT_DIR", "/opt/sgfood/dbt/sgfood")
DBT_FLAGS = "--profiles-dir . --no-use-colors"


def dbt(command: str) -> str:
    return f"cd {DBT_DIR} && {DBT_BIN} {command} {DBT_FLAGS}"


def alerta_fallo(context) -> None:
    """Callback de fallo: deja una alerta clara en el log de la tarea.
    (En producción aquí se enviaría un correo/Slack.)"""
    ti = context["task_instance"]
    log.error(
        "ALERTA SG-Food | DAG=%s | tarea=%s | run=%s | intento=%s | error=%s",
        ti.dag_id, ti.task_id, context["run_id"], ti.try_number, context.get("exception"),
    )


default_args = {
    "owner": "grupo9",
    "retries": 2,
    "retry_delay": timedelta(seconds=30),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(minutes=20),
    "on_failure_callback": alerta_fallo,
}


@dag(
    dag_id="sgfood_elt",
    description="ELT SG-Food: OLTP + CSV -> raw -> dbt -> marts -> validaciones",
    schedule="0 6 * * *",  # diario 06:00 hora de Guatemala
    start_date=pendulum.datetime(2026, 10, 1, tz="America/Guatemala"),
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    doc_md=__doc__,
    tags=["sgfood", "elt", "dbt", "proyecto1"],
    params={
        "inyectar_casos_calidad": Param(
            False,
            type="boolean",
            description="Inserta en raw los casos de casos_calidad_opcionales.csv para demostrar que dbt los detecta.",
        ),
    },
)
def sgfood_elt():
    @task
    def preparar_lote() -> str:
        """Id del lote determinista por corrida: reintentar la corrida reutiliza el mismo lote."""
        run_id = get_current_context()["run_id"]
        batch_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"sgfood/{run_id}"))
        log.info("Lote %s para la corrida %s", batch_id, run_id)
        return batch_id

    @task
    def verificar_fuentes() -> dict:
        from sgfood_elt.pipeline import check_sources

        return check_sources()

    @task_group(group_id="extraccion_carga")
    def extraccion_carga(batch_id: str):
        @task
        def listar_tablas_oltp() -> list[str]:
            from sgfood_elt.pipeline import oltp_table_names

            return oltp_table_names()

        @task
        def listar_archivos_csv() -> list[str]:
            from sgfood_elt.pipeline import csv_file_names

            return csv_file_names()

        @task(map_index_template="{{ tabla }}")
        def cargar_tabla_oltp(table_name: str, batch_id: str) -> int:
            from sgfood_elt.pipeline import load_oltp_table

            context = get_current_context()
            context["tabla"] = table_name
            return load_oltp_table(table_name, batch_id, context["run_id"])

        @task(map_index_template="{{ archivo }}")
        def cargar_csv(file_name: str, batch_id: str) -> int:
            from sgfood_elt.pipeline import load_csv_file

            context = get_current_context()
            context["archivo"] = file_name
            return load_csv_file(file_name, batch_id, context["run_id"])

        cargar_tabla_oltp.partial(batch_id=batch_id).expand(table_name=listar_tablas_oltp())
        cargar_csv.partial(batch_id=batch_id).expand(file_name=listar_archivos_csv())

    @task.branch
    def decidir_inyeccion() -> str:
        if get_current_context()["params"]["inyectar_casos_calidad"]:
            return "inyectar_casos_calidad"
        return "sin_inyeccion"

    @task(retries=0)
    def inyectar_casos_calidad(batch_id: str) -> int:
        from sgfood_elt.quality_cases import inject_quality_cases

        return inject_quality_cases(batch_id, get_current_context()["run_id"])

    @task_group(group_id="transformacion_dbt")
    def transformacion_dbt():
        deps = BashOperator(task_id="dbt_deps", bash_command=dbt("deps"))
        freshness = BashOperator(task_id="dbt_source_freshness", bash_command=dbt("source freshness"))
        # Un fallo de prueba de datos no se arregla reintentando: solo 1 reintento (fallos transitorios)
        staging = BashOperator(task_id="dbt_build_staging", bash_command=dbt("build --select staging"), retries=1)
        marts = BashOperator(
            task_id="dbt_build_marts", bash_command=dbt("build --select intermediate marts"), retries=1
        )
        docs = BashOperator(task_id="dbt_docs_generate", bash_command=dbt("docs generate"))
        deps >> freshness >> staging >> marts >> docs

    @task(retries=0)
    def validaciones_sql(batch_id: str) -> dict:
        from sgfood_elt.validate import run_validations

        return run_validations(batch_id)

    @task(trigger_rule=TriggerRule.ALL_DONE, retries=0)
    def resumen_ejecucion(batch_id: str) -> dict:
        """Corre siempre (aunque algo haya fallado) para dejar el registro de la corrida."""
        from sgfood_elt.pipeline import record_pipeline_run

        summary = record_pipeline_run(batch_id, get_current_context()["run_id"])
        if summary["status"] != "SUCCESS":
            raise AirflowFailException(f"Corrida con errores: {summary['detail']}")
        return summary

    batch_id = preparar_lote()
    fuentes_ok = verificar_fuentes()
    carga = extraccion_carga(batch_id)
    rama = decidir_inyeccion()
    inyeccion = inyectar_casos_calidad(batch_id)
    sin_inyeccion = EmptyOperator(task_id="sin_inyeccion")
    datos_en_raw = EmptyOperator(task_id="datos_en_raw", trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS)
    dbt_tg = transformacion_dbt()
    validaciones = validaciones_sql(batch_id)
    resumen = resumen_ejecucion(batch_id)

    batch_id >> fuentes_ok >> carga >> rama
    rama >> [inyeccion, sin_inyeccion] >> datos_en_raw
    datos_en_raw >> dbt_tg >> validaciones >> resumen


sgfood_elt()
