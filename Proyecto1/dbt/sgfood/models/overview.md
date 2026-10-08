{% docs __overview__ %}
# SG-Food · Data Warehouse

Proyecto 1 · Seminario de Sistemas 2 · USAC 2S2026 · Grupo 9

Flujo **ELT**: Python carga las fuentes en `raw`, dbt transforma por capas:

| Capa | Schema | Materialización | Propósito |
|---|---|---|---|
| Sources | `raw` | tablas (Python) | Copia fiel de la BD transaccional y los CSV |
| Staging | `staging` | vistas | Tipado, limpieza y renombrado 1:1; pruebas de calidad de entrada |
| Intermediate | `intermediate` | vistas | Joins y reglas de negocio (promoción atribuida, devoluciones valorizadas) |
| Marts · core | `marts` | tablas con contrato | Esquema estrella: 7 dimensiones y 5 hechos con PK/FK |
| Marts · reporting | `marts` | tablas | Agregados para el tablero (metas, alertas de inventario) |

Las filas que fallan una prueba se guardan en el schema `test_failures`.
{% enddocs %}
