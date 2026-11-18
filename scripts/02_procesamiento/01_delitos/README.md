# Procesamiento de Delitos de Alto Impacto (SDSCJ / SIEDCO)

Este módulo lee los microdatos oficiales mensuales de la Secretaría de Seguridad (`data/raw/delitos/SIEDCO.csv`), filtra las 19 localidades urbanas y las tres modalidades objetivo (*Hurto a personas*, *Hurto a residencias* y *Hurto motocicletas*) entre enero de 2022 y septiembre de 2026, completa la malla balanceada localidad x mes (`19 × 57 = 1.083` filas) y genera el panel mensual base de delitos.

---

## 1. Entradas y Salidas

* **Entrada (Data Raw):** `data/raw/delitos/SIEDCO.csv`
* **Salida (Data Processed):** `data/processed/01_delitos/delitos_localidad_mensual.parquet`
* **Unidad de Análisis:** Localidad urbana ($i = 1, \dots, 19$) por mes (`fecha_mes`, `2022-01-01` a `2026-09-01`).
* **Dimensiones:** `1.083` observaciones exactas (`19 localidades × 57 meses`).

---

## 2. Variables Procesadas

1. `codigo_localidad`: Código oficial estandarizado en formato texto de dos dígitos (`01` a `19`).
2. `localidad`: Nombre en formato título con tildes y caracteres castellanos corregidos.
3. `año`: Entero entre `2022` y `2026`.
4. `mes`: Entero entre `1` y `12` (hasta `9` en `2026`).
5. `fecha_mes`: Fecha del primer día de cada mes (`Date`, `2022-01-01` a `2026-09-01`).
6. `hurto_personas`: Conteo mensual oficial de denuncias de hurto a personas (`HURTO A PERSONAS`).
7. `hurto_residencias`: Conteo mensual de hurto a residencias (`HURTO A RESIDENCIAS`).
8. `hurto_motos`: Conteo mensual de hurto de motocicletas (`HURTO MOTOCICLETAS`).

---

## 3. Ejecución

```r
source(here::here("scripts", "02_procesamiento", "01_delitos", "procesamiento_delitos.R"))
```
