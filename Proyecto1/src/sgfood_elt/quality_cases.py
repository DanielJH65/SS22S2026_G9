"""Inyección controlada de datos inválidos (casos_calidad_opcionales.csv).

NO forma parte de la corrida principal. Sirve para demostrar que las pruebas de
dbt detectan cada tipo de error. Cada caso se inserta en raw como una copia de
una fila real con el campo indicado alterado; las llaves se cambian a valores
990000+ para no colisionar con datos reales. Las filas quedan marcadas con
_source = 'quality_case:<tipo>' y desaparecen en la siguiente carga completa.
"""
from __future__ import annotations

import csv
import logging

from psycopg import sql
from psycopg.rows import dict_row

from .audit import track_load
from .config import ConfigError, data_dir, dw_config, load_pipeline_config
from .db import connect

log = logging.getLogger(__name__)

KEY_BASE = 990000

# entidad -> (tabla raw, función que devuelve las columnas a ajustar para el caso n)
CASE_RULES = {
    "cliente":             ("raw.oltp_cliente",            lambda n: {"id_cliente": KEY_BASE + n}),
    "producto":            ("raw.oltp_producto",           lambda n: {"id_producto": KEY_BASE + n, "sku": f"QA{KEY_BASE + n}"}),
    "venta":               ("raw.oltp_venta",              lambda n: {"id_venta": KEY_BASE + n}),
    "venta_detalle":       ("raw.oltp_venta_detalle",      lambda n: {"id_detalle": KEY_BASE + n}),
    "inventario":          ("raw.csv_inventario_bodega",   lambda n: {"fecha_corte": "2026-09-30"}),
    "proveedores_precios": ("raw.csv_proveedores_precios", lambda n: {"fecha_vigencia": "2026-09-30"}),
    "metas_ventas":        ("raw.csv_metas_ventas",        lambda n: {"periodo": "2026-09"}),
    "devoluciones":        ("raw.csv_devoluciones",        lambda n: {"id_devolucion": str(KEY_BASE + n)}),
}


def inject_quality_cases(batch_id: str, dag_run_id: str | None = None) -> int:
    cfg = load_pipeline_config()
    path = data_dir() / cfg["quality_cases"]["file"]
    with open(path, encoding="utf-8-sig", newline="") as fh:
        cases = list(csv.DictReader(fh))

    with (
        track_load(batch_id, path.name, "raw.*", "append", dag_run_id) as stats,
        connect(dw_config()) as dw,
        dw.transaction(),
        dw.cursor(row_factory=dict_row) as cur,
    ):
        stats.rows_extracted = len(cases)
        for n, case in enumerate(cases, start=1):
            entity, field = case["entidad"].strip(), case["campo"].strip()
            if entity not in CASE_RULES:
                raise ConfigError(f"Entidad de prueba desconocida: {entity}")
            target, key_overrides = CASE_RULES[entity]
            schema, table = target.split(".")
            ident = sql.Identifier(schema, table)

            # Fila real que sirve de plantilla (distinta para cada caso)
            cur.execute(
                sql.SQL(
                    "SELECT * FROM {} WHERE _source NOT LIKE 'quality_case%%' "
                    "ORDER BY 1, 2, 3 OFFSET %s LIMIT 1"
                ).format(ident),
                (n,),
            )
            template = cur.fetchone()
            if template is None:
                raise RuntimeError(f"{target} está vacía: ejecute primero la carga principal")
            if field not in template:
                raise ConfigError(f"{target} no tiene la columna {field}")

            row = {k: v for k, v in template.items() if k not in ("_loaded_at", "_row_number")}
            row.update(key_overrides(n))
            row[field] = case["valor_prueba"].strip() or None
            row["_batch_id"] = batch_id
            row["_source"] = f"quality_case:{case['tipo_incidencia'].strip()}"

            cur.execute(
                sql.SQL("INSERT INTO {} ({}) VALUES ({})").format(
                    ident,
                    sql.SQL(", ").join(map(sql.Identifier, row)),
                    sql.SQL(", ").join(sql.Placeholder() * len(row)),
                ),
                list(row.values()),
            )
            stats.rows_loaded += 1
            log.warning("Caso de calidad inyectado en %s: %s = %r (%s)",
                        target, field, row[field], case["tipo_incidencia"])

    return stats.rows_loaded
