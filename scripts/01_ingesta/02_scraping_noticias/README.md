# Ingesta y Scraping de Noticias en Google News

En esta carpeta está el código para obtener, consolidar y expandir las noticias de prensa y comunicados sobre hurtos y seguridad en las 19 localidades urbanas de Bogotá.

El método garantiza **trazabilidad completa**, **conservación de subtablas por localidad** y un mecanismo de **recolección rápida y sin bloqueos mediante Google News RSS** que complementa los datos históricos.

---

## 1. Estructura de Datos y Trazabilidad

Para que cualquier persona pueda auditar cómo se construyó la base final, conservamos tanto las subtablas brutas de cada localidad como el archivo unificado:

```text
data/raw/noticias/
├── historico_por_localidad/            # Subtablas brutas individuales (4.276 filas en total)
│   ├── antonio_narino.parquet (.rds)
│   ├── barrios_unidos.parquet (.rds)
│   ├── bosa.parquet (.rds)
│   ├── ... (19 localidades urbanas)
│   └── usme.parquet (.rds)
├── chunk_rss_*.parquet                 # Lotes descargados vía Google News RSS (1.703 noticias)
└── cobertura_historica.json            # Metadatos de meses y fechas ya cubiertos por localidad

data/raw/
├── noticias_google_news_consolidado.parquet   # Base final validada (3.928 noticias únicas 2022 a sept 2026)
└── noticias_google_news_consolidado.rds       # Respaldo en formato nativo de R
```

---

## 2. Flujo de Trabajo Metodológico y Procedural

El script `scraping_google_news.R` opera con un **flujo lineal secuencial (Paso 1 a Paso 7)**, sin complejas funciones envolventes anidadas, permitiendo su ejecución de arriba hacia abajo o paso a paso con `Ctrl + Enter` en RStudio:

```mermaid
flowchart TD
    A["Paso 1: Parámetros del proyecto<br/>(2022-01-01 a 2026-09-30)"] --> B["Paso 2: Diccionario de 19 localidades<br/>y utilidades de limpieza"]
    B --> C["Paso 3: Bucle de recolección RSS<br/>(news.google.com/rss/search)"]
    C --> D["Paso 4: Carga y unión vertical<br/>(Base previa + Chunks Parquet)"]
    D --> E["Paso 5: Deduplicación dual y filtro<br/>(Por URL limpia y por título exacto)"]
    E --> F["Paso 6: Exportación columnar<br/>(Parquet, RDS y cobertura_historica.json)"]
    F --> G["Paso 7: Diagnóstico y Auditoría<br/>(Distribución por año, top localidades y 0 NAs)"]
```

---

## 3. Scripts Disponibles

### `00_consolidar_subtablas_historicas.R`
* **¿Qué hace?** Lee las carpetas originales de las 19 localidades, guarda cada subtabla en `historico_por_localidad/` (formato Parquet y RDS), ejecuta la consolidación y validación territorial, exporta `noticias_google_news_consolidado.parquet` y crea el archivo `cobertura_historica.json`.
* **Garantía:** Reproduce con precisión matemática las filas del estudio original sin pérdida de información.

### `scraping_google_news.R`
* **¿Qué hace?** Automatiza la recolección, limpieza, deduplicación y consolidación de noticias para las 19 localidades mediante un flujo lineal secuencial y el **motor oficial Google News RSS**.
* **Ventajas clave:**
  * Flujo procedimental paso a paso: fácil de leer, depurar y evaluar sin capas de funciones abstractas.
  * No requiere navegador web ni drivers de Selenium.
  * No genera bloqueos por IP ni reCAPTCHAs.
  * Captura fecha real exacta de publicación (`pubDate`), medio de comunicación (`source`), titular y enlace limpio.
  * Parámetros explícitos en el encabezado (`FECHA_INICIO_ANALISIS`, `FECHA_FIN_ANALISIS`).
* **Auditoría del corpus:** Genera automáticamente métricas de volumen por año (2022-2026), distribución territorial y chequeo de NAs.
* **Ejecución típica:**
  ```r
  source(here::here("scripts", "01_ingesta", "02_scraping_noticias", "scraping_google_news.R"))
  ```

### `test_scraping_noticias.R`
* **¿Qué hace?** Batería de 15 pruebas automatizadas que valida la sintaxis booleana, exclusiones deportivas, codificación de URLs, limpieza de enlaces de tracking, fallback de cuerpo e integridad del dataset consolidado.
* **Ejecución de pruebas:**
  ```r
  source(here::here("scripts", "01_ingesta", "02_scraping_noticias", "test_scraping_noticias.R"))
  ```

---

## 4. Cobertura Histórica y Expansión Futura

* **Periodo cubierto en subtablas históricas:** Enero de 2022 a Septiembre de 2025 (2.533 noticias previas).
* **Expansión con Google News RSS:** 1.395 artículos adicionales deduplicados cubriendo hasta septiembre de 2026.
* **Total consolidado actual:** **3.928 noticias únicas** cubriendo desde `2022-01-01` hasta `2026-09-30` con 0 valores nulos en campos esenciales.
