"""Extracción desde las fuentes.

Ambos extractores devuelven (columnas, iterador de filas) y leen en streaming:
la memoria usada no depende del tamaño de la fuente.
"""
from __future__ import annotations

import csv
import logging
from datetime import date
from pathlib import Path
from typing import Iterator

import psycopg
from psycopg import sql

log = logging.getLogger(__name__)


class SchemaMismatchError(ValueError):
    """El archivo no tiene las columnas esperadas (cambio de esquema en la fuente)."""


def extract_oltp_table(
    conn: psycopg.Connection,
    schema: str,
    table_cfg: dict,
    since: date | None = None,
    itersize: int = 2000,
) -> tuple[list[str], Iterator[tuple]]:
    """Lee una tabla del OLTP con un cursor del lado del servidor.

    since=None extrae la tabla completa; con fecha, aplica el filtro incremental.
    """
    name = table_cfg["name"]
    params: dict = {}
    if since is None:
        query = sql.SQL("SELECT * FROM {}").format(sql.Identifier(schema, name))
    elif "watermark_query" in table_cfg:
        query = sql.SQL(table_cfg["watermark_query"])
        params = {"since": since}
    else:
        query = sql.SQL("SELECT * FROM {} WHERE {} >= %(since)s").format(
            sql.Identifier(schema, name), sql.Identifier(table_cfg["watermark_column"])
        )
        params = {"since": since}

    cur = conn.cursor(name=f"extract_{name}")
    cur.itersize = itersize
    cur.execute(query, params)
    columns = [col.name for col in cur.description]
    log.info("Extrayendo %s.%s%s", schema, name, f" desde {since}" if since else " (completa)")

    def rows() -> Iterator[tuple]:
        try:
            yield from cur
        finally:
            cur.close()

    return columns, rows()


def extract_csv(
    path: Path,
    expected_columns: list[str],
    encoding: str = "utf-8-sig",
    delimiter: str = ",",
) -> tuple[list[str], Iterator[tuple]]:
    """Lee un CSV validando su encabezado.

    Limpieza técnica mínima (no de negocio): recorta espacios, convierte celdas
    vacías en NULL, omite líneas en blanco y agrega el número de fila del archivo
    (_row_number) para trazar cualquier error hasta su origen.
    """
    if not path.exists():
        raise FileNotFoundError(f"No existe el archivo fuente {path}")

    fh = open(path, encoding=encoding, newline="")
    reader = csv.reader(fh, delimiter=delimiter)
    try:
        header = [h.strip().lower() for h in next(reader)]
    except StopIteration:
        fh.close()
        raise SchemaMismatchError(f"{path.name} está vacío") from None

    if header != expected_columns:
        fh.close()
        raise SchemaMismatchError(
            f"{path.name}: columnas {header} no coinciden con las esperadas {expected_columns}"
        )
    log.info("Extrayendo %s", path.name)

    def rows() -> Iterator[tuple]:
        try:
            for row_number, row in enumerate(reader, start=2):  # fila 1 = encabezado
                if not any(cell.strip() for cell in row):
                    continue
                if len(row) != len(header):
                    raise SchemaMismatchError(
                        f"{path.name} fila {row_number}: {len(row)} columnas, se esperaban {len(header)}"
                    )
                values = [cell.strip() or None for cell in row]
                yield (*values, row_number)
        finally:
            fh.close()

    return [*header, "_row_number"], rows()
