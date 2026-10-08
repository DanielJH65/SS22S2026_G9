"""Configura Metabase automáticamente vía su API (solo librería estándar).

1. Crea el usuario administrador (primer arranque).
2. Registra el Data Warehouse con el usuario de solo lectura bi_reader
   (solo ve el schema marts).

Uso (con Metabase arriba: docker compose --profile bi up -d):
    python scripts/setup_metabase.py
Variables opcionales en .env: METABASE_PORT, METABASE_ADMIN_EMAIL, METABASE_ADMIN_PASSWORD.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_env() -> dict:
    env = {}
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip()
    env.update({k: v for k, v in os.environ.items() if k in env})
    return env


ENV = load_env()
BASE = f"http://localhost:{ENV.get('METABASE_PORT', '3000')}/api"
ADMIN_EMAIL = ENV.get("METABASE_ADMIN_EMAIL", "admin@sgfood.local")
ADMIN_PASSWORD = ENV.get("METABASE_ADMIN_PASSWORD", "SgFood#2026")


def api(method: str, path: str, body: dict | None = None, session: str | None = None):
    req = urllib.request.Request(f"{BASE}{path}", method=method)
    req.add_header("Content-Type", "application/json")
    if session:
        req.add_header("X-Metabase-Session", session)
    data = json.dumps(body).encode() if body is not None else None
    with urllib.request.urlopen(req, data=data, timeout=60) as resp:
        raw = resp.read()
        return json.loads(raw) if raw else None


def wait_until_ready(timeout_s: int = 900) -> None:
    """El primer arranque de Metabase (migraciones internas) puede tardar ~10 min."""
    start = time.time()
    while time.time() - start < timeout_s:
        try:
            if api("GET", "/health").get("status") == "ok":
                return
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            pass
        print("Esperando a Metabase...")
        time.sleep(10)
    sys.exit("Metabase no respondió a tiempo")


def get_session() -> str:
    props = api("GET", "/session/properties")
    token = props.get("setup-token")
    if token and not props.get("has-user-setup"):
        print("Primer arranque: creando administrador", ADMIN_EMAIL)
        result = api("POST", "/setup", {
            "token": token,
            "user": {"first_name": "Admin", "last_name": "SG-Food", "email": ADMIN_EMAIL,
                     "password": ADMIN_PASSWORD, "site_name": "SG-Food"},
            "prefs": {"site_name": "SG-Food", "site_locale": "es", "allow_tracking": False},
        })
        return result["id"]
    return api("POST", "/session", {"username": ADMIN_EMAIL, "password": ADMIN_PASSWORD})["id"]


def ensure_database(session: str) -> int:
    name = "SG-Food Data Warehouse"
    for db in api("GET", "/database", session=session)["data"]:
        if db["name"] == name:
            print("La base ya estaba registrada (id", db["id"], ")")
            return db["id"]
    db = api("POST", "/database", {
        "engine": "postgres",
        "name": name,
        "details": {
            "host": "dw-db",            # nombre del servicio dentro de la red de Docker
            "port": 5432,
            "dbname": ENV.get("DW_DB", "sgfood_dw"),
            "user": ENV.get("BI_READER_USER", "bi_reader"),
            "password": ENV.get("BI_READER_PASSWORD", "bi_reader_pwd"),
            "schema-filters-type": "inclusion",
            "schema-filters-patterns": "marts",
            "ssl": False,
        },
    }, session=session)
    print("Base registrada (id", db["id"], ")")
    return db["id"]


DASHBOARD_NAME = "SG-Food · Ventas e Inventario"

VALIDAS = "FROM marts.fct_ventas f WHERE f.es_venta_valida"

# (título, display, SQL, visualization_settings, (fila, columna, ancho, alto))
CARDS = [
    ("Venta neta total (Q)", "scalar",
     f"SELECT sum(f.monto_neto) AS venta_neta {VALIDAS}", {}, (0, 0, 6, 3)),
    ("Margen bruto %", "scalar",
     f"SELECT round(sum(f.margen_bruto) / sum(f.monto_neto) * 100, 2) AS margen_pct {VALIDAS}", {}, (0, 6, 6, 3)),
    ("Número de ventas", "scalar",
     f"SELECT count(DISTINCT f.id_venta) AS ventas {VALIDAS}", {}, (0, 12, 6, 3)),
    ("Tasa de devolución %", "scalar",
     "SELECT round((SELECT sum(monto_devuelto) FROM marts.fct_devoluciones) / "
     "sum(f.monto_neto) * 100, 2) AS tasa_devolucion_pct " + VALIDAS, {}, (0, 18, 6, 3)),
    ("Venta neta mensual", "line",
     "SELECT d.anio_mes, sum(f.monto_neto) AS venta_neta, sum(f.margen_bruto) AS margen_bruto "
     "FROM marts.fct_ventas f JOIN marts.dim_fecha d ON d.sk_fecha = f.sk_fecha "
     "WHERE f.es_venta_valida GROUP BY d.anio_mes ORDER BY d.anio_mes",
     {"graph.dimensions": ["anio_mes"], "graph.metrics": ["venta_neta", "margen_bruto"]}, (3, 0, 12, 6)),
    ("Venta neta por categoría", "bar",
     "SELECT p.categoria, sum(f.monto_neto) AS venta_neta "
     "FROM marts.fct_ventas f JOIN marts.dim_producto p ON p.sk_producto = f.sk_producto "
     "WHERE f.es_venta_valida GROUP BY p.categoria ORDER BY venta_neta DESC",
     {"graph.dimensions": ["categoria"], "graph.metrics": ["venta_neta"]}, (3, 12, 12, 6)),
    ("Venta real vs meta por mes", "bar",
     "SELECT anio_mes, sum(venta_neta) AS venta_real, sum(meta_ventas) AS meta "
     "FROM marts.mart_cumplimiento_metas GROUP BY anio_mes ORDER BY anio_mes",
     # Un solo eje Y: con dos ejes la meta (~10x mayor) parecería igual a la venta real
     {"graph.dimensions": ["anio_mes"], "graph.metrics": ["venta_real", "meta"],
      "graph.y_axis.auto_split": False}, (9, 0, 12, 6)),
    ("Cumplimiento de meta por sucursal %", "bar",
     "SELECT nombre_sucursal, round(sum(venta_neta) / sum(meta_ventas) * 100, 2) AS cumplimiento_pct "
     "FROM marts.mart_cumplimiento_metas GROUP BY nombre_sucursal ORDER BY cumplimiento_pct DESC",
     {"graph.dimensions": ["nombre_sucursal"], "graph.metrics": ["cumplimiento_pct"]}, (9, 12, 12, 6)),
    ("Devoluciones por motivo (Q)", "pie",
     "SELECT motivo, sum(monto_devuelto) AS monto_devuelto FROM marts.fct_devoluciones GROUP BY motivo",
     {"pie.dimension": "motivo", "pie.metric": "monto_devuelto"}, (15, 0, 8, 6)),
    ("Top 10 productos por venta", "bar",
     "SELECT p.nombre_producto, sum(f.monto_neto) AS venta_neta "
     "FROM marts.fct_ventas f JOIN marts.dim_producto p ON p.sk_producto = f.sk_producto "
     "WHERE f.es_venta_valida GROUP BY p.nombre_producto ORDER BY venta_neta DESC LIMIT 10",
     {"graph.dimensions": ["nombre_producto"], "graph.metrics": ["venta_neta"]}, (15, 8, 16, 6)),
    ("Alertas de inventario (último corte)", "table",
     "SELECT nombre_sucursal, sku, nombre_producto, stock_disponible, stock_minimo, "
     "unidades_promedio_mes, meses_cobertura, dias_para_vencer, estado_stock "
     "FROM marts.mart_alertas_inventario WHERE estado_stock <> 'OK' OR vence_en_60_dias "
     "ORDER BY estado_stock, unidades_promedio_mes DESC",
     {}, (21, 0, 24, 8)),
]


def ensure_dashboard(session: str, db_id: int) -> int:
    for dash in api("GET", "/dashboard", session=session):
        if dash["name"] == DASHBOARD_NAME and not dash.get("archived"):
            print("El tablero ya existía (id", dash["id"], ")")
            return dash["id"]

    dashcards = []
    for i, (title, display, query, viz, (row, col, size_x, size_y)) in enumerate(CARDS, start=1):
        card = api("POST", "/card", {
            "name": title,
            "display": display,
            "dataset_query": {"database": db_id, "type": "native", "native": {"query": query}},
            "visualization_settings": viz,
        }, session=session)
        dashcards.append({"id": -i, "card_id": card["id"], "row": row, "col": col,
                          "size_x": size_x, "size_y": size_y,
                          "parameter_mappings": [], "visualization_settings": {}})
    dash = api("POST", "/dashboard", {
        "name": DASHBOARD_NAME,
        "description": "Ventas, metas, devoluciones e inventario. Fuente: schema marts (dbt).",
    }, session=session)
    api("PUT", f"/dashboard/{dash['id']}", {"dashcards": dashcards}, session=session)
    print(f"Tablero creado (id {dash['id']}) con {len(dashcards)} tarjetas")
    return dash["id"]


def public_link(session: str, dashboard_id: int) -> str:
    """Enlace público de solo lectura (útil para capturas y para la calificación)."""
    api("PUT", "/setting/enable-public-sharing", {"value": True}, session=session)
    uuid = api("POST", f"/dashboard/{dashboard_id}/public_link", {}, session=session)["uuid"]
    return f"http://localhost:{ENV.get('METABASE_PORT', '3000')}/public/dashboard/{uuid}"


def main() -> None:
    wait_until_ready()
    session = get_session()
    db_id = ensure_database(session)
    api("POST", f"/database/{db_id}/sync_schema", {}, session=session)
    dashboard_id = ensure_dashboard(session, db_id)
    # El tablero del proyecto como página de inicio (en lugar de las exploraciones automáticas)
    api("PUT", "/setting/custom-homepage", {"value": True}, session=session)
    api("PUT", "/setting/custom-homepage-dashboard", {"value": dashboard_id}, session=session)
    port = ENV.get("METABASE_PORT", "3000")
    print(f"Listo: http://localhost:{port}/dashboard/{dashboard_id}  (usuario {ADMIN_EMAIL})")
    print("Enlace público:", public_link(session, dashboard_id))


if __name__ == "__main__":
    main()
