"""Carga al schema raw con COPY (el método masivo más rápido de PostgreSQL).

Toda carga ocurre en UNA transacción: si algo falla, raw queda exactamente como
estaba antes (nunca a medias).
"""
from __future__ import annotations

from typing import Iterable

import psycopg
from psycopg import sql

META_COLUMNS = ["_batch_id", "_source"]  # _loaded_at toma DEFAULT now()


def _split(target: str) -> sql.Identifier:
    schema, table = target.split(".", 1)
    return sql.Identifier(schema, table)


def _copy_rows(
    cur: psycopg.Cursor,
    table: sql.Identifier,
    columns: list[str],
    rows: Iterable[tuple],
    meta: tuple,
) -> int:
    stmt = sql.SQL("COPY {} ({}) FROM STDIN").format(
        table, sql.SQL(", ").join(map(sql.Identifier, [*columns, *META_COLUMNS]))
    )
    count = 0
    with cur.copy(stmt) as copy:
        for row in rows:
            copy.write_row((*row, *meta))
            count += 1
    return count


def full_load(
    conn: psycopg.Connection,
    target: str,
    columns: list[str],
    rows: Iterable[tuple],
    meta: tuple,
) -> int:
    """TRUNCATE + COPY atómico: re-ejecutar produce siempre el mismo resultado."""
    table = _split(target)
    with conn.transaction(), conn.cursor() as cur:
        cur.execute(sql.SQL("TRUNCATE TABLE {}").format(table))
        return _copy_rows(cur, table, columns, rows, meta)


def merge_load(
    conn: psycopg.Connection,
    target: str,
    columns: list[str],
    rows: Iterable[tuple],
    meta: tuple,
    key_column: str,
) -> int:
    """Carga incremental: COPY a una tabla temporal y reemplazo por llave.

    Las filas re-extraídas por el lookback sustituyen a su versión anterior,
    así un cambio de estado en la fuente se refleja sin duplicar registros.
    """
    table = _split(target)
    tmp = sql.Identifier("tmp_merge")
    key = sql.Identifier(key_column)
    with conn.transaction(), conn.cursor() as cur:
        cur.execute(
            sql.SQL("CREATE TEMP TABLE {} (LIKE {} INCLUDING DEFAULTS) ON COMMIT DROP").format(tmp, table)
        )
        count = _copy_rows(cur, tmp, columns, rows, meta)
        cur.execute(
            sql.SQL("DELETE FROM {t} AS t USING {s} AS s WHERE t.{k} = s.{k}").format(t=table, s=tmp, k=key)
        )
        cur.execute(sql.SQL("INSERT INTO {} SELECT * FROM {}").format(table, tmp))
        return count


def count_rows(conn: psycopg.Connection, target: str, batch_id: str | None = None) -> int:
    """Conteo de reconciliación tras la carga (total o solo del lote)."""
    table = _split(target)
    if batch_id is None:
        query = sql.SQL("SELECT count(*) FROM {}").format(table)
        return conn.execute(query).fetchone()[0]
    query = sql.SQL("SELECT count(*) FROM {} WHERE _batch_id = %s").format(table)
    return conn.execute(query, (batch_id,)).fetchone()[0]
