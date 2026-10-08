"""Conexiones a PostgreSQL con reintentos ante fallos transitorios."""
from __future__ import annotations

import logging
import time

import psycopg

from .config import DbConfig

log = logging.getLogger(__name__)


def connect(
    cfg: DbConfig,
    *,
    autocommit: bool = False,
    read_only: bool = False,
    attempts: int = 3,
    backoff_seconds: float = 2.0,
) -> psycopg.Connection:
    """Abre una conexión; reintenta con backoff exponencial si la BD no responde."""
    for attempt in range(1, attempts + 1):
        try:
            conn = psycopg.connect(
                host=cfg.host,
                port=cfg.port,
                dbname=cfg.dbname,
                user=cfg.user,
                password=cfg.password,
                autocommit=autocommit,
                connect_timeout=10,
                application_name="sgfood_elt",
            )
            conn.read_only = read_only
            return conn
        except psycopg.OperationalError as exc:
            if attempt == attempts:
                raise
            wait = backoff_seconds * 2 ** (attempt - 1)
            log.warning(
                "No se pudo conectar a %s:%s/%s (intento %d/%d): %s. Reintento en %.0fs",
                cfg.host, cfg.port, cfg.dbname, attempt, attempts, exc, wait,
            )
            time.sleep(wait)
    raise AssertionError("inalcanzable")
