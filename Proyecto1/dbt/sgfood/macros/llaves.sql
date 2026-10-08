{#
  Llaves sustitutas de las dimensiones: md5 de la llave natural (determinista).
  sk_desconocido() es la llave del "miembro desconocido" (llave natural = -1):
  los hechos la usan cuando no encuentran su dimensión (FK huérfana).
#}
{% macro sk(columnas) -%}
    cast({{ dbt_utils.generate_surrogate_key(columnas) }} as varchar(32))
{%- endmacro %}

{% macro sk_desconocido() -%}
    cast(md5('-1') as varchar(32))
{%- endmacro %}

{# Llave entera YYYYMMDD de dim_fecha a partir de una fecha #}
{% macro sk_fecha(columna_fecha) -%}
    cast(to_char({{ columna_fecha }}, 'YYYYMMDD') as integer)
{%- endmacro %}
