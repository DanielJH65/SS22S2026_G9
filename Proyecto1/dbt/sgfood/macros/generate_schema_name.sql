{#
  Usa el nombre de schema configurado tal cual (staging, marts, ...) en lugar del
  comportamiento por defecto de dbt (<schema_base>_<custom>, ej. public_marts).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
