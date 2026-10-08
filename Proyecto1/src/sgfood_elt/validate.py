"""Validaciones SQL post-transformación.

Ejecuta los bloques "-- @check:" de sql/validation/*.sql (cada uno devuelve las
filas que incumplen una regla) más la reconciliación OLTP -> raw, que se hace
aquí porque son dos bases de datos distintas. Todo resultado queda en
audit.validation_result; si falla un check de severidad "error" se lanza
ValidationError para que la tarea (y el DAG) falle.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from pathlib import Path

from psycopg import sql

from .config import PROJECT_ROOT, dw_config, load_pipeline_config, oltp_config
from .db import connect

log = logging.getLogger(__name__)

VALIDATION_DIR = PROJECT_ROOT / "sql" / "validation"
CHECK_HEADER = re.compile(
    r"^--\s*@check:\s*(?P<name>\w+)\s*\|\s*tipo:\s*(?P<type>\w+)\s*\|\s*severidad:\s*(?P<severity>error|warn)\s*$",
    re.MULTILINE,
)


class ValidationError(RuntimeError):
    """Uno o más checks de severidad error encontraron filas inválidas."""


@dataclass
class Check:
    name: str
    check_type: str
    severity: str
    query: str
    source: str


@dataclass
class CheckResult:
    name: str
    check_type: str
    severity: str
    failing_rows: int

    @property
    def passed(self) -> bool:
        return self.failing_rows == 0


def parse_checks(directory: Path = VALIDATION_DIR) -> list[Check]:
    """Separa cada archivo en bloques por su encabezado "-- @check:"."""
    checks = []
    for path in sorted(directory.glob("*.sql")):
        text = path.read_text(encoding="utf-8")
        headers = list(CHECK_HEADER.finditer(text))
        for i, header in enumerate(headers):
            end = headers[i + 1].start() if i + 1 < len(headers) else len(text)
            query = text[header.end():end].strip().rstrip(";").strip()
            checks.append(Check(header["name"], header["type"], header["severity"], query, path.name))
    if not checks:
        raise ValidationError(f"No se encontraron checks en {directory}")
    return checks


def _reconcile_oltp_vs_raw() -> list[CheckResult]:
    cfg = load_pipeline_config()
    schema = cfg["oltp"]["schema"]
    results = []
    with connect(oltp_config(), read_only=True) as src, connect(dw_config()) as dw:
        for table in cfg["oltp"]["tables"]:
            src_count = src.execute(
                sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(schema, table["name"]))
            ).fetchone()[0]
            target_schema, target_table = table["target"].split(".")
            raw_count = dw.execute(
                sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(target_schema, target_table))
            ).fetchone()[0]
            diff = abs(src_count - raw_count)
            if diff:
                log.error("OLTP %s=%d vs %s=%d", table["name"], src_count, table["target"], raw_count)
            results.append(CheckResult(f"reconciliacion_oltp_raw_{table['name']}", "conteo", "error", diff))
    return results


def run_validations(batch_id: str) -> dict:
    results = _reconcile_oltp_vs_raw()

    with connect(dw_config(), autocommit=True) as dw:
        for check in parse_checks():
            failing = len(dw.execute(check.query).fetchall())
            results.append(CheckResult(check.name, check.check_type, check.severity, failing))

        with dw.cursor() as cur:
            cur.executemany(
                """
                INSERT INTO audit.validation_result
                    (batch_id, check_name, check_type, severity, failing_rows, passed)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                [(batch_id, r.name, r.check_type, r.severity, r.failing_rows, r.passed) for r in results],
            )

    for r in results:
        level = logging.INFO if r.passed else (logging.ERROR if r.severity == "error" else logging.WARNING)
        log.log(level, "%-45s %-15s %-5s %s", r.name, r.check_type, r.severity,
                "OK" if r.passed else f"{r.failing_rows} filas")

    errors = [r.name for r in results if not r.passed and r.severity == "error"]
    summary = {
        "total": len(results),
        "passed": sum(r.passed for r in results),
        "warned": sum(not r.passed and r.severity == "warn" for r in results),
        "failed": len(errors),
    }
    log.info("Validaciones: %s", summary)
    if errors:
        raise ValidationError(f"{len(errors)} validaciones críticas fallaron: {', '.join(errors)}")
    return summary
