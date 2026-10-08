{#
  Prueba genérica personalizada: el valor debe ser una proporción entre 0 y 1
  (descuentos y porcentajes de promoción se guardan como 0.15 = 15 %).
  Devuelve las filas inválidas; la prueba pasa si no devuelve ninguna.
#}
{% test porcentaje_valido(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} < 0
   or {{ column_name }} > 1

{% endtest %}
