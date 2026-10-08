"""Tareas de Extract & Load. Son las funciones que invoca Airflow (una por tabla
o archivo) y también la CLI (`python -m sgfood_elt`)."""
from __future__ import annotations

import logging
from datetime import date, timedelta

from psycopg import sql

from .audit import get_watermark, set_watermark, track_load
from .config import (
    data_dir,
    dw_config,
    find_csv_file,
    find_oltp_table,
    load_pipeline_config,
    oltp_config,
)
from .db import connect
from .extract import extract_csv, extract_oltp_table
from .load import count_rows, full_load, merge_load

log = logging.getLogger(__name__)


class ReconciliationError(RuntimeError):
    """Las filas en destino no cuadran con las extraídas de la fuente."""


def _reconcile(expected: int, actual: int, target: str) -> None:
    if expected != actual:
        raise ReconciliationError(f"{target}: se extrajeron {expected} filas pero hay {actual} en destino")


def load_oltp_table(table_name: str, batch_id: str, dag_run_id: str | None = None) -> int:
    """Extrae una tabla del OLTP y la carga en raw.oltp_<tabla>. Devuelve filas cargadas."""
    cfg = load_pipeline_config()
    schema = cfg["oltp"]["schema"]
    table_cfg = find_oltp_table(cfg, table_name)
    target = table_cfg["target"]
    mode = table_cfg.get("mode", "full")
    source_name = f"{schema}.{table_name}"

    with (
        track_load(batch_id, source_name, target, mode, dag_run_id) as stats,
        connect(oltp_config(), read_only=True) as src,
        connect(dw_config()) as dw,
    ):
        since = None
        if mode == "incremental":
            last = get_watermark(dw, source_name)
            if last:
                since = date.fromisoformat(last) - timedelta(days=table_cfg.get("lookback_days", 0))

        columns, rows = extract_oltp_table(src, schema, table_cfg, since)
        meta = (batch_id, source_name)

        if mode == "full":
            stats.rows_loaded = full_load(dw, target, columns, rows, meta)
            stats.rows_extracted = stats.rows_loaded
            _reconcile(stats.rows_extracted, count_rows(dw, target), target)
        elif mode == "incremental":
            stats.rows_loaded = merge_load(dw, target, columns, rows, meta, table_cfg["key_column"])
            stats.rows_extracted = stats.rows_loaded
            _reconcile(stats.rows_extracted, count_rows(dw, target, batch_id), target)
            _advance_watermark(src, dw, schema, table_cfg, source_name)
            dw.commit()
        else:
            raise ValueError(f"Modo de carga desconocido '{mode}' para {table_name}")

    return stats.rows_loaded


def _advance_watermark(src, dw, schema: str, table_cfg: dict, source_name: str) -> None:
    column = table_cfg["watermark_column"]
    if "watermark_max_query" in table_cfg:
        query = sql.SQL(table_cfg["watermark_max_query"])
    else:
        query = sql.SQL("SELECT max({}) FROM {}").format(
            sql.Identifier(column), sql.Identifier(schema, table_cfg["name"])
        )
    new_value = src.execute(query).fetchone()[0]
    if new_value is not None:
        set_watermark(dw, source_name, column, str(new_value))
        log.info("Watermark de %s = %s", source_name, new_value)


def load_csv_file(file_name: str, batch_id: str, dag_run_id: str | None = None) -> int:
    """Valida un CSV y lo carga completo en raw.csv_<archivo>. Devuelve filas cargadas."""
    cfg = load_pipeline_config()
    csv_cfg = cfg["csv"]
    file_cfg = find_csv_file(cfg, file_name)
    target = file_cfg["target"]
    path = data_dir() / csv_cfg["directory"] / file_name

    with (
        track_load(batch_id, file_name, target, "full", dag_run_id) as stats,
        connect(dw_config()) as dw,
    ):
        columns, rows = extract_csv(
            path,
            file_cfg["columns"],
            encoding=csv_cfg.get("encoding", "utf-8-sig"),
            delimiter=csv_cfg.get("delimiter", ","),
        )
        stats.rows_loaded = full_load(dw, target, columns, rows, (batch_id, file_name))
        stats.rows_extracted = stats.rows_loaded
        _reconcile(stats.rows_extracted, count_rows(dw, target), target)

    return stats.rows_loaded


def check_sources() -> dict:
    """Verificación previa: las fuentes y el DW responden y existe todo lo que se va
    a extraer. Falla rápido y con un mensaje claro antes de lanzar las cargas."""
    cfg = load_pipeline_config()
    schema = cfg["oltp"]["schema"]

    with connect(oltp_config(), read_only=True) as src:
        existing = {
            row[0]
            for row in src.execute(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = %s", (schema,)
            )
        }
    missing_tables = [t["name"] for t in cfg["oltp"]["tables"] if t["name"] not in existing]

    csv_dir = data_dir() / cfg["csv"]["directory"]
    missing_files = [f["file"] for f in cfg["csv"]["files"] if not (csv_dir / f["file"]).exists()]

    with connect(dw_config()) as dw:
        dw.execute("SELECT 1 FROM raw.oltp_venta LIMIT 0")

    if missing_tables or missing_files:
        raise RuntimeError(
            f"Fuentes incompletas. Tablas OLTP faltantes: {missing_tables or 'ninguna'}; "
            f"CSV faltantes en {csv_dir}: {missing_files or 'ninguno'}"
        )
    log.info("Fuentes OK: %d tablas OLTP y %d archivos CSV", len(existing), len(cfg["csv"]["files"]))
    return {"tablas_oltp": len(cfg["oltp"]["tables"]), "archivos_csv": len(cfg["csv"]["files"])}


def record_pipeline_run(batch_id: str, dag_run_id: str | None = None) -> dict:
    """Consolida en audit.pipeline_run el resultado de la corrida (cargas + validaciones)."""
    with connect(dw_config(), autocommit=True) as dw:
        loads_ok, loads_failed = dw.execute(
            """
            SELECT count(*) FILTER (WHERE status = 'SUCCESS'),
                   count(*) FILTER (WHERE status <> 'SUCCESS')
            FROM audit.etl_load_log WHERE batch_id = %s
            """,
            (batch_id,),
        ).fetchone()
        passed, failed, warned = dw.execute(
            """
            SELECT count(*) FILTER (WHERE passed),
                   count(*) FILTER (WHERE NOT passed AND severity = 'error'),
                   count(*) FILTER (WHERE NOT passed AND severity = 'warn')
            FROM audit.validation_result WHERE batch_id = %s
            """,
            (batch_id,),
        ).fetchone()

        problems = []
        if loads_failed:
            problems.append(f"{loads_failed} cargas fallidas")
        if passed + failed + warned == 0:
            problems.append("las validaciones no se ejecutaron (falló una etapa previa)")
        if failed:
            problems.append(f"{failed} validaciones críticas fallidas")
        status = "FAILED" if problems else "SUCCESS"
        detail = "; ".join(problems) or f"{warned} advertencias de calidad"

        dw.execute(
            """
            INSERT INTO audit.pipeline_run
                (batch_id, dag_run_id, status, loads_ok, loads_failed,
                 checks_passed, checks_failed, checks_warned, detail, finished_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, now())
            ON CONFLICT (batch_id) DO UPDATE SET
                status = EXCLUDED.status, loads_ok = EXCLUDED.loads_ok,
                loads_failed = EXCLUDED.loads_failed, checks_passed = EXCLUDED.checks_passed,
                checks_failed = EXCLUDED.checks_failed, checks_warned = EXCLUDED.checks_warned,
                detail = EXCLUDED.detail, finished_at = now()
            """,
            (batch_id, dag_run_id, status, loads_ok, loads_failed, passed, failed, warned, detail),
        )
    summary = {"status": status, "loads_ok": loads_ok, "loads_failed": loads_failed,
               "checks_passed": passed, "checks_failed": failed, "checks_warned": warned, "detail": detail}
    log.info("Resumen del lote %s: %s", batch_id, summary)
    return summary


def oltp_table_names() -> list[str]:
    return [t["name"] for t in load_pipeline_config()["oltp"]["tables"]]


def csv_file_names() -> list[str]:
    return [f["file"] for f in load_pipeline_config()["csv"]["files"]]
