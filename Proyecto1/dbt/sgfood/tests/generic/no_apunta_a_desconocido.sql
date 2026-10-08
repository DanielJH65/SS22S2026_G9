{#
  Prueba genérica personalizada: detecta filas de un hecho cuya llave foránea
  terminó en el "miembro desconocido" (-1 / md5('-1')), es decir, registros
  cuya dimensión no existía en la fuente (FK huérfana que llegó hasta marts).
#}
{% test no_apunta_a_desconocido(model, column_name) %}

select *
from {{ model }}
where cast({{ column_name }} as text) in ('-1', md5('-1'))

{% endtest %}
