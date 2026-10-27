# Ingesta de Delitos de Alto Impacto y Cartografía de Bogotá (SDSCJ)

Este módulo gestiona la descarga oficial y reproducible de la capa espacial y estadística de Delitos de Alto Impacto (DAI) reportados por la Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ) y SIEDCO.

---

## 1. Fuente y Ficha Técnica

* **Entidad:** Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ) / Policía Nacional (SIEDCO).
* **Portal:** [Datos Abiertos Bogotá - Delito de Alto Impacto](https://datosabiertos.bogota.gov.co/dataset/delito-de-alto-impacto-bogota-d-c).
* **Archivo de Salida:** `data/raw/delitos/localidades_bogota_raw.geojson`.
* **Corte Temporal:** 2018 a Septiembre 2026 (`CMMES: Ene-Sep (2018vs2026)`).
* **Contenido:** Polígonos de las 20 localidades del Distrito Capital (más código 99 sin localización) con el conteo anual y acumulado de las 12 modalidades de delitos de alto impacto (hurto a personas, comercio, residencias, automotores, motocicletas, homicidios, extorsión, etc.).

---

## 2. Ejecución

Desde la raíz del proyecto en R:

```r
source(here::here("scripts", "01_ingesta", "01_delitos", "descarga_delitos_sdscj.R"))
```
