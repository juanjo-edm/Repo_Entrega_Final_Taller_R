# Procesamiento Demográfico y Tasas de Hurto (SDS)

Este módulo procesa las proyecciones de población distrital de la Secretaría de Salud ([`data/raw/poblacion/poblacion_localidades_raw.parquet`](file:///data/raw/poblacion/poblacion_localidades_raw.parquet)), unifica los nombres de las 19 localidades urbanas, calcula la población residente proyectada por año y la cruza con el panel de delitos para calcular las tasas oficiales de hurto por cada 100.000 habitantes.

---

## 1. Entradas y Salidas

* **Entradas:**
  * `data/raw/poblacion/poblacion_localidades_raw.parquet` (Microdatos demográficos SDS)
  * `data/processed/01_delitos/delitos_localidad_anual.parquet` (Generado por `02_procesamiento/01_delitos/`)
* **Salida (Data Processed):** `data/processed/02_poblacion/panel_delitos_poblacion_localidad.parquet`
* **Unidad de Análisis:** Localidad urbana ($i = 1, \dots, 19$) por año ($t = 2022, \dots, 2026$).
* **Dimensiones:** 95 observaciones exactas (19 localidades × 5 años).

---

## 2. Variables del Panel Resultante

1. `codigo_localidad`: Código DANE/Distrital de dos dígitos (`01` a `19`).
2. `localidad`: Nombre oficial estandarizado de la localidad.
3. `año`: Entero (2022 a 2026).
4. `hurto_personas`: Total de denuncias de hurto a personas.
5. `hurto_residencias`: Total de denuncias de hurto a residencias.
6. `hurto_motos`: Total de denuncias de hurto a motocicletas.
7. `poblacion`: Denominador demográfico proyectado por la SDS.
8. `tasa_hurto_personas`: Hurto a personas por cada 100.000 habitantes.
9. `tasa_hurto_residencias`: Hurto a residencias por cada 100.000 habitantes.
10. `tasa_hurto_motos`: Hurto a motocicletas por cada 100.000 habitantes.
11. `tasa_hurto_total`: Suma de las 3 modalidades de hurto por cada 100.000 habitantes.

---

## 3. Ejecución

```r
source(here::here("scripts", "02_procesamiento", "02_poblacion", "procesamiento_poblacion.R"))
```
