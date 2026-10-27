# Ingesta de Proyecciones de Población por Localidad (SDS)

Este módulo gestiona la descarga reproducible de las proyecciones de población distrital y por localidad de la Secretaría Distrital de Salud (SDS) para el cálculo de tasas delictivas por cada 100.000 habitantes.

---

## 1. Fuente y Ficha Técnica

* **Entidad:** Secretaría Distrital de Salud (SDS).
* **Portal:** [Datos Abiertos Bogotá - Pirámide Poblacional](https://datosabiertos.bogota.gov.co/dataset/piramide-poblacional-bogota-d-c).
* **Archivo de Salida:** `data/raw/poblacion/poblacion_localidades_raw.parquet`.
* **Corte Temporal:** 2005 a 2035 (proyecciones oficiales continuas).
* **Contenido:** Población desagregada por localidad, año, sexo, edad y grupos quinquenales / curso de vida.

---

## 2. Ejecución

Desde la raíz del proyecto en R:

```r
source(here::here("scripts", "01_ingesta", "02_poblacion", "descarga_poblacion_sds.R"))
```
