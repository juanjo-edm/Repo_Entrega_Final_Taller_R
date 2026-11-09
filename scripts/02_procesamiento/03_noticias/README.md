# Procesamiento y Depuración Textual de Noticias (NLP, T-05, T-06 y DAI)

Este submódulo contiene el pipeline unificado de procesamiento en lenguaje natural (NLP), estructuración rectangular para `sentometrics` (Tareas **T-05** y **T-06**) y clasificación temática sobre el corpus periodístico crudo recolectado en `data/raw/noticias/`.

El procesamiento se encuentra completamente consolidado en un único script:
* [`procesamiento_noticias.R`](procesamiento_noticias.R):
  1. **Consolidación rectangular y slugs canónicos sin guiones (T-01 y T-05):** Lectura con `arrow::read_parquet()` y `data.table::as.data.table()`, asignación de identificador único canónico (`id = "doc_1"..."doc_3916"`) y homologación de las 19 localidades urbanas en `localidad_slug` usando exclusivamente minúsculas y guion bajo (`_`), garantizando cero guiones medios (`-`) para compatibilidad con las fórmulas internas de `sentometrics`.
  2. **Depuración higiénica del cuerpo editorial y remoción de HTML (T-06):** Eliminación de etiquetas HTML residuales (`<[^>]+>`), entidades web (`&nbsp;`, `&quot;`, `&amp;`), avisos de cookies, cuñas publicitarias, metadatos multimedia de IA de Google y URLs, aplicando *fallback* al resumen informativo cuando el cuerpo limpio tiene menos de 40 caracteres.
  3. **Cálculo de métricas de volumen léxico:** `palabras_cuerpo`, `caracteres_cuerpo`, `palabras_titulo` y construcción del campo unificado `texto_completo_nlp` con cero valores `NA`.
  4. **Filtro temático riguroso y reclasificación DAI:** Clasificación basada en límites de palabra (`\b`) según los 11 Delitos de Alto Impacto (DAI) oficiales de la Secretaría Distrital de Seguridad, Convivencia y Justicia (SDSCJ).
  5. **Banderas de calidad metodológica:** `confianza_dai`, `fecha_imputada`, `menciona_localidad`, `texto_corto`, `ventana_ene_sep`.

---

## 1. Entradas y Salidas

* **Entrada (Data Raw):** `data/raw/noticias/noticias_google_news_consolidado.parquet`
* **Salida Principal (Data Processed):**
  * `data/processed/03_noticias/noticias_procesadas.parquet`: Corpus único íntegro y depurado (3.916 noticias) con `id`, `localidad_slug` (sin `-`), variables de longitud léxica, `texto_completo_nlp`, clasificación oficial DAI (`delito_sdscj`, `es_dai_amplio`, `confianza_dai`) e indicadores de calidad.
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
