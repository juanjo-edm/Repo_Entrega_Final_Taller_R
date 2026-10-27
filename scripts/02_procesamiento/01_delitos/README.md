# Procesamiento de Delitos de Alto Impacto (SDSCJ)

Este módulo toma la capa cartográfica y estadística cruda de la Secretaría de Seguridad ([`data/raw/delitos/localidades_bogota_raw.geojson`](file:///data/raw/delitos/localidades_bogota_raw.geojson)), extrae las series anuales delictivas (2022–2026), dinamiza las variables a formato largo (*tidy data*) y genera el panel base de delitos por localidad.

---

## 1. Entradas y Salidas

* **Entrada (Data Raw):** `data/raw/delitos/localidades_bogota_raw.geojson`
* **Salida (Data Processed):** `data/processed/01_delitos/delitos_localidad_anual.parquet`
* **Unidad de Análisis:** Localidad urbana ($i = 1, \dots, 19$) por año ($t = 2022, \dots, 2026$).
* **Dimensiones:** 95 observaciones exactas (19 localidades × 5 años).

---

## 2. Variables Procesadas

1. `codigo_localidad`: Código oficial estandarizado en formato texto de dos dígitos (`01` a `19`).
2. `localidad`: Nombre en formato título con tildes y caracteres castellanos corregidos.
3. `año`: Entero entre 2022 y 2026.
4. `hurto_personas`: Conteo anual oficial de denuncias de hurto a personas (`CMHP`).
5. `hurto_residencias`: Conteo anual de hurto a residencias (`CMHR`).
6. `hurto_motos`: Conteo anual de hurto a motocicletas (`CMHM`).

---

## 3. Ejecución

```r
source(here::here("scripts", "02_procesamiento", "01_delitos", "procesamiento_delitos.R"))
```
