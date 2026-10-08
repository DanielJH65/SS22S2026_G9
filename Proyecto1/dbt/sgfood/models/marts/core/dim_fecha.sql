-- Dimensión calendario generada (no proviene de ninguna fuente).
-- Rango configurable con las vars fecha_inicio_dim / fecha_fin_dim.
with dias as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('fecha_inicio_dim') ~ "' as date)",
        end_date="cast('" ~ var('fecha_fin_dim') ~ "' as date) + interval '1 day'"
    ) }}
),

fechas as (
    select cast(date_day as date) as fecha from dias
)

select
    {{ sk_fecha('fecha') }}                                   as sk_fecha,
    fecha,
    cast(extract(year from fecha) as smallint)                as anio,
    cast(extract(quarter from fecha) as smallint)             as trimestre,
    cast(extract(month from fecha) as smallint)               as mes,
    cast(case extract(month from fecha)
        when 1 then 'Enero'      when 2 then 'Febrero'   when 3 then 'Marzo'
        when 4 then 'Abril'      when 5 then 'Mayo'      when 6 then 'Junio'
        when 7 then 'Julio'      when 8 then 'Agosto'    when 9 then 'Septiembre'
        when 10 then 'Octubre'   when 11 then 'Noviembre' when 12 then 'Diciembre'
    end as varchar(15))                                       as nombre_mes,
    cast(to_char(fecha, 'YYYY-MM') as char(7))                as anio_mes,
    cast(extract(week from fecha) as smallint)                as semana_iso,
    cast(extract(day from fecha) as smallint)                 as dia_mes,
    cast(extract(isodow from fecha) as smallint)              as dia_semana_iso,
    cast(case extract(isodow from fecha)
        when 1 then 'Lunes'   when 2 then 'Martes'  when 3 then 'Miércoles'
        when 4 then 'Jueves'  when 5 then 'Viernes' when 6 then 'Sábado'
        when 7 then 'Domingo'
    end as varchar(15))                                       as nombre_dia,
    extract(isodow from fecha) in (6, 7)                      as es_fin_de_semana
from fechas

union all

-- Miembro desconocido
select
    -1, cast(null as date), null, null, null,
    cast('Desconocido' as varchar(15)), null, null, null, null,
    cast('Desconocido' as varchar(15)), null
