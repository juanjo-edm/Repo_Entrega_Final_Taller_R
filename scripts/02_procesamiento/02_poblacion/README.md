# Procesamiento Demográfico y Tasas Mensuales de Hurto (SDS)

Este módulo procesa las proyecciones de población distrital de la Secretaría de Salud ([`data/raw/poblacion/poblacion_localidades_raw.parquet`](../../../data/raw/poblacion/poblacion_localidades_raw.parquet)), unifica los nombres de las 19 localidades urbanas, calcula la población residente proyectada por año y la cruza con el panel mensual de delitos para calcular las tasas oficiales mensuales de hurto por cada 100.000 habitantes.

---

## 1. Entradas y Salidas

* **Entradas:**
  * `data/raw/poblacion/poblacion_localidades_raw.parquet` (Microdatos demográficos SDS)
  * `data/processed/01_delitos/delitos_localidad_mensual.parquet` (Generado por `02_procesamiento/01_delitos/`)
* **Salida (Data Processed):** `data/processed/02_poblacion/panel_delitos_poblacion_mensual.parquet`
* **Unidad de Análisis:** Localidad urbana ($i = 1, \dots, 19$) por mes (`fecha_mes`, `2022-01-01` a `2026-09-01`).
* **Dimensiones:** `1.083` observaciones exactas (`19 localidades × 57 meses`) × `13` columnas.

---

## 2. Variables del Panel Resultante

1. `codigo_localidad`: Código DANE/Distrital de dos dígitos (`01` a `19`).
2. `localidad`: Nombre oficial estandarizado de la localidad.
3. `año`: Entero (`2022` a `2026`).
4. `mes`: Entero (`1` a `12`).
5. `fecha_mes`: Primer día del mes (`Date`).
6. `hurto_personas`: Conteo mensual de denuncias de hurto a personas.
7. `hurto_residencias`: Conteo mensual de denuncias de hurto a residencias.
8. `hurto_motos`: Conteo mensual de denuncias de hurto de motocicletas.
9. `poblacion`: Denominador demográfico anual proyectado por la SDS.
10. `tasa_hurto_personas`: Hurto mensual a personas por cada 100.000 habitantes.
11. `tasa_hurto_residencias`: Hurto mensual a residencias por cada 100.000 habitantes.
12. `tasa_hurto_motos`: Hurto mensual de motocicletas por cada 100.000 habitantes.
13. `tasa_hurto_total`: Suma mensual de las 3 modalidades de hurto por cada 100.000 habitantes.

---

## 3. Ejecución

```r
source(here::here("scripts", "02_procesamiento", "02_poblacion", "procesamiento_poblacion.R"))
```
