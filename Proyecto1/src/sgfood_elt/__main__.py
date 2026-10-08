"""CLI para ejecutar el Extract & Load fuera de Airflow.

Ejemplos (desde Proyecto1/, con PYTHONPATH=src):
    python -m sgfood_elt                       # todo: OLTP + CSV
    python -m sgfood_elt --oltp venta cliente  # solo esas tablas
    python -m sgfood_elt --csv                 # todos los CSV
    python -m sgfood_elt --inject-quality-cases
"""
from __future__ import annotations

import argparse
import logging
import sys
import uuid

from .pipeline import csv_file_names, load_csv_file, load_oltp_table, oltp_table_names
from .quality_cases import inject_quality_cases
from .validate import ValidationError, run_validations

log = logging.getLogger("sgfood_elt")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="sgfood_elt", description="Extract & Load SG-Food -> raw")
    parser.add_argument("--oltp", nargs="*", metavar="TABLA", help="tablas OLTP (sin nombres = todas)")
    parser.add_argument("--csv", nargs="*", metavar="ARCHIVO", help="archivos CSV (sin nombres = todos)")
    parser.add_argument("--inject-quality-cases", action="store_true",
                        help="inserta en raw los casos de casos_calidad_opcionales.csv")
    parser.add_argument("--validate", action="store_true",
                        help="solo ejecuta las validaciones SQL (después de dbt)")
    parser.add_argument("--batch-id", default=str(uuid.uuid4()))
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)-7s %(name)s: %(message)s")

    if args.validate:
        try:
            run_validations(args.batch_id)
        except ValidationError as exc:
            log.error("%s", exc)
            return 1
        return 0

    run_all = args.oltp is None and args.csv is None and not args.inject_quality_cases
    tasks = []
    if run_all or args.oltp is not None:
        for name in args.oltp or oltp_table_names():
            tasks.append((f"oltp:{name}", load_oltp_table, name))
    if run_all or args.csv is not None:
        for name in args.csv or csv_file_names():
            tasks.append((f"csv:{name}", load_csv_file, name))

    log.info("Lote %s: %d cargas", args.batch_id, len(tasks))
    failures = []
    for label, func, name in tasks:
        try:
            func(name, args.batch_id)
        except Exception:  # se continúa con las demás y se reporta al final
            log.exception("Falló %s", label)
            failures.append(label)

    if args.inject_quality_cases:
        inject_quality_cases(args.batch_id)

    if failures:
        log.error("Lote %s terminó con %d fallos: %s", args.batch_id, len(failures), ", ".join(failures))
        return 1
    log.info("Lote %s terminado sin errores", args.batch_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
