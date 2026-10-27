# Procesamiento y Depuración Textual de Noticias (NLP y DAI)

Este submódulo contiene el pipeline unificado de procesamiento en lenguaje natural (NLP) y clasificación temática sobre el corpus periodístico crudo recolectado en `data/raw/noticias/`.

El procesamiento se encuentra completamente consolidado en un único script:
* [`procesamiento_noticias.R`](file:///scripts/02_procesamiento/03_noticias/procesamiento_noticias.R):
  1. Depuración higiénica del cuerpo editorial (remoción de cookies, cuñas publicitarias, metadatos multimedia de IA, URLs y normalización tipográfica).
  2. Cálculo de métricas de volumen léxico (`palabras_cuerpo`, `caracteres_cuerpo`, `palabras_titulo`).
  3. Filtro temático riguroso y reclasificación basada en límites de palabra (`\b`) según los 11 Delitos de Alto Impacto (DAI) oficiales de la Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ).
  4. Generación de banderas de calidad metodológica (`confianza_dai`, `fecha_imputada`, `menciona_localidad`, `texto_corto`, `ventana_ene_sep`).

---

## 1. Entradas y Salidas

* **Entrada (Data Raw):** `data/raw/noticias/noticias_google_news_consolidado.parquet`
* **Salida Principal (Data Processed):**
  * `data/processed/03_noticias/noticias_procesadas.parquet`: Corpus único íntegro y depurado (3.916 noticias) con todas las variables de longitud léxica, clasificación oficial DAI (`delito_sdscj`, `es_dai_amplio`, `confianza_dai`) e indicadores de calidad.
* **Salidas de Auditoría (`output/tables/`):**
  * `tabla_reclasificacion_dai.csv`: Matriz de reclasificación original vs. SDSCJ.
  * `tabla_conteo_localidad_anio_dai.csv`: Panel de volumen noticioso por localidad y año.
  * `muestra_validacion_manual_dai.csv`: 195 artículos estratificados para validación manual de precisión.

---

## 2. Ejecución

```r
# Ejecución integral de procesamiento y clasificación de noticias
source(here::here("scripts", "02_procesamiento", "03_noticias", "procesamiento_noticias.R"))
```
