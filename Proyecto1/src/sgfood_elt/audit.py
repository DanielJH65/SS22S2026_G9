"""Trazabilidad del pipeline: bitácora de cargas y watermarks (schema audit)."""
from __future__ import annotations

import logging
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Iterator

import psycopg

from .config import dw_config
from .db import connect

log = logging.getLogger(__name__)


@dataclass
class LoadStats:
    rows_extracted: int = 0
    rows_loaded: int = 0


@contextmanager
def track_load(
    batch_id: str,
    source_name: str,
    target_table: str,
    load_mode: str,
    dag_run_id: str | None = None,
) -> Iterator[LoadStats]:
    """Registra una carga en audit.etl_load_log (RUNNING -> SUCCESS | FAILED).

    Usa una conexión autocommit propia: si la carga falla y su transacción hace
    rollback, el registro del fallo igual queda guardado.
    """
    stats = LoadStats()
    with connect(dw_config(), autocommit=True) as conn:
        id_log = conn.execute(
            """
            INSERT INTO audit.etl_load_log
                (batch_id, dag_run_id, source_name, target_table, load_mode)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id_log
            """,
            (batch_id, dag_run_id, source_name, target_table, load_mode),
        ).fetchone()[0]
        try:
            yield stats
        except Exception as exc:
            conn.execute(
                """
                UPDATE audit.etl_load_log
                   SET status = 'FAILED', finished_at = now(),
                       rows_extracted = %s, rows_loaded = %s, error_message = %s
                 WHERE id_log = %s
                """,
                (stats.rows_extracted, stats.rows_loaded, f"{type(exc).__name__}: {exc}"[:4000], id_log),
            )
            log.error("Carga FALLIDA %s -> %s: %s", source_name, target_table, exc)
            raise
        conn.execute(
            """
            UPDATE audit.etl_load_log
               SET status = 'SUCCESS', finished_at = now(),
                   rows_extracted = %s, rows_loaded = %s
             WHERE id_log = %s
            """,
            (stats.rows_extracted, stats.rows_loaded, id_log),
        )
        log.info(
            "Carga OK %s -> %s (%s): %d extraídas, %d cargadas",
            source_name, target_table, load_mode, stats.rows_extracted, stats.rows_loaded,
        )


def get_watermark(conn: psycopg.Connection, source_name: str) -> str | None:
    row = conn.execute(
        "SELECT last_value FROM audit.load_watermark WHERE source_name = %s",
        (source_name,),
    ).fetchone()
    return row[0] if row else None


def set_watermark(conn: psycopg.Connection, source_name: str, column: str, value: str) -> None:
    conn.execute(
        """
        INSERT INTO audit.load_watermark (source_name, watermark_col, last_value, updated_at)
        VALUES (%s, %s, %s, now())
        ON CONFLICT (source_name) DO UPDATE
           SET watermark_col = EXCLUDED.watermark_col,
               last_value    = EXCLUDED.last_value,
               updated_at    = now()
        """,
        (source_name, column, value),
    )
