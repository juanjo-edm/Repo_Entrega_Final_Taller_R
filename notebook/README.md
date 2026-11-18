# Cuadernos Quarto (`notebook/`)

En esta carpeta se encuentran los cuadernos metodológicos y guías de estudio/código del proyecto desarrollados en Quarto (`.qmd`) bajo `metodologia/`. Las entregas evaluativas formales del curso se trasladaron a [`output/entregas/`](../output/entregas/README.md).

```text
notebook/
├── README.md
└── metodologia/
    ├── 02_modelado_clustering_sentometrics.qmd       # Guía metodológica y pedagógica integral
    ├── 02_modelado_clustering_sentometrics.html      # Reporte interactivo con código y gráficos
    ├── 02_modelado_clustering_sentometrics.pdf
    └── instrucciones_codigo/                         # Guías línea a línea de cada etapa del código en R
        ├── 03_ingesta_tasas_poblacion.pdf
        ├── 04_modelo_kmeans_clusters.pdf
        ├── 05_flujo_delitos_ingesta_procesamiento.pdf
        ├── 06_flujo_noticias_scraping_procesamiento.pdf
        ├── 07_flujo_sentometrics_elasticnet_shiny.pdf
        └── qmd/                                      # Fuentes Quarto (.qmd) en diseño doble columna
            ├── 03_ingesta_tasas_poblacion.qmd
            ├── 04_modelo_kmeans_clusters.qmd
            ├── 05_flujo_delitos_ingesta_procesamiento.qmd
            ├── 06_flujo_noticias_scraping_procesamiento.qmd
            └── 07_flujo_sentometrics_elasticnet_shiny.qmd
```

---

## 1. Entregas académicas (ahora en [`output/entregas/`](../output/entregas/README.md))

Los documentos evaluativos de Primera Entrega (`01_entrega_1_propuesta_eda.*`, `01_propuesta_retroalimentada_evaluador.pdf` y `01_respuestas_evaluador_entrega_1.*`) junto con las plantillas de Co-evaluación (Grupo 1), Presentación Plenaria y Documento Final ahora residen en [`output/entregas/`](../output/entregas/README.md).

```bash
# Compilar la Entrega 1 desde su nueva ruta:
quarto render output/entregas/01_primera_entrega/01_entrega_1_propuesta_eda.qmd --to pdf

# Compilar plantilla del Documento Final (máx. 5 páginas + Anexos):
quarto render output/entregas/04_documento_final/documento_final_grupo_3.qmd --to pdf
```

---

## 2. Subcarpeta `notebook/metodologia/`

Aloja el cuaderno metodológico maestro y las cinco guías didácticas de código que documentan el pipeline reproducible en R (las guías de estudio para sustentación se encuentran ahora en [`output/guia_estudio/`](../../output/guia_estudio/README.md)). Sigue de manera estricta los estándares de programación declarados en [`docs/guias/estandares_programacion.md`](../docs/guias/estandares_programacion.md).

### 2.1 Cuaderno metodológico integral

* [**`02_modelado_clustering_sentometrics.qmd`**](metodologia/02_modelado_clustering_sentometrics.qmd) ([HTML](metodologia/02_modelado_clustering_sentometrics.html) | [PDF](metodologia/02_modelado_clustering_sentometrics.pdf)):
  * **Objetivo:** Servir como manual de estudio y replicación paso a paso de toda la metodología, integrando los paneles mensuales de `SIEDCO.csv` (`data/processed/01_delitos/`, `02_poblacion/`), el corpus de prensa (`03_noticias/`), los clústeres `K-Means`, el artefacto consolidado `sentometrics_pipeline.rds` y las tablas de `output/tables/`.
  * **Secciones del cuaderno (0 a 7):**
    0. **Configuración inicial y arquitectura:** Entorno reproducible, contrato de insumos base y esquema general del pipeline.
    1. **Datos de partida (`#sec-datos`):** Curaduría de microdatos mensuales `SIEDCO.csv`, proyecciones SDS, Google News RSS, desambiguación geográfica y clasificación oficial SDSCJ (`3.916` notas totales; `993` objetivo de las 3 modalidades comparables).
    2. **Tasas delictivas por 100.000 habitantes (`#sec-tasas`):** Formulación matemática e intuición del sesgo de denominador por población flotante (2022–septiembre de 2026).
    3. **Agrupamiento espacial con $K$-Means (`#sec-kmeans`):** Estandarización Z-score, optimización Hartigan-Wong, criterio de Silueta ($K^* = 3$, silueta media `0,5211`, partición `13 / 5 / 1` con `0` siluetas negativas), sensibilidad multiescalar/Tidymodels (PCA, PAM, AGNES, GMM) y perfiles (*Residencial y Periférico* `13`, *Céntrico e Institucional* `5`, *Comercial y Automotor* `1`: Los Mártires).
    4. **Diagnóstico del corpus y análisis de sentimiento con `sentometrics` (`#sec-sentometrics`):** Descriptivos del corpus (Figuras 3–10, incluyendo facetas legibles de las `6` covariables objetivo en `facet_wrap()`), `corpus_sento` filtrado a las **`993` noticias objetivo** con `6` *features* binarias sin guiones (`3` clústeres + `3` modalidades de hurto), diccionarios (`nrc_es`, `crimen_es`) con modificadores de valencia ($t \in \{1,2,3,4\}$), explicación tabular de `ctr_agg()`, agregación en tres niveles ($2 \times 6 \times 3 = 36$ series mensuales con ventana `lag = 6` y curvas `linear`, `exponential0.5`, `beta22`) y extracción de extremos (`peakdocs()` con tabla y gráfico divergente, `peakdates()`).
    5. **Modelado econométrico supervisado (Elastic Net) y `attributions()` (`#sec-elasticnet`):** Verificación de frecuencia mensual en `SIEDCO.csv` y noticias, desglose elemento a elemento de la ecuación objetiva Elastic Net, estimación regularizada calibrada por $\text{BIC}$ ($h = 1$ mes, $M = 36 < N = 51$, $\alpha^* = 0,5$, $R^2 = 88,99\,\%$) y descomposición aditiva de atribuciones.
    6. **Cartografía espacial desagregada e integración para R Shiny (`#sec-mapa`):** Mapas `{sf}` desagregados por modalidad de hurto, conteo y tono mediático (`993` objetivo frente a `3.916` de referencia), además del flujo hacia `sentometrics_pipeline.rds` y `datos_consolidados_shiny.rds`.
    7. **Verificación de consistencia y conclusiones (`#sec-conclusiones`):** Auditoría de integridad sobre los objetos calculados en memoria y síntesis final.

### Cómo compilar el cuaderno de metodología:
```bash
quarto render notebook/metodologia/02_modelado_clustering_sentometrics.qmd --to html
quarto render notebook/metodologia/02_modelado_clustering_sentometrics.qmd --to pdf
```

---

## 3. Guías de estudio para sustentación (ahora en [`output/guia_estudio/`](../output/guia_estudio/README.md))

Las guías de estudio fueron trasladadas y ampliadas por componente en [`output/guia_estudio/`](../output/guia_estudio/README.md) (`01_metodologia_sustentacion/`, `02_presentacion_plenaria/`, `03_documento_final/` y `04_aplicacion_shiny/`):

```bash
quarto render output/guia_estudio/01_metodologia_sustentacion/01_guia_estudio_metodologia_sustentacion.qmd --to pdf
```

---

## 4. Subcarpeta `notebook/metodologia/instrucciones_codigo/` (`03` a `07`)

Cada cuaderno se compila en PDF con diseño a doble columna (código exacto numerado a la izquierda y explicación línea por línea a la derecha, junto con diagramas de flujo TikZ). Los `.qmd` fuente están en [`metodologia/instrucciones_codigo/qmd/`](metodologia/instrucciones_codigo/qmd/) y los PDFs compilados en [`metodologia/instrucciones_codigo/`](metodologia/instrucciones_codigo/):

* [**`03_ingesta_tasas_poblacion.pdf`**](metodologia/instrucciones_codigo/03_ingesta_tasas_poblacion.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/03_ingesta_tasas_poblacion.qmd)): Explica `descarga_poblacion_sds.R` y `procesamiento_poblacion.R` (proyecciones SDS y tasas por 100.000 habitantes).
* [**`04_modelo_kmeans_clusters.pdf`**](metodologia/instrucciones_codigo/04_modelo_kmeans_clusters.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/04_modelo_kmeans_clusters.qmd)): Explica `04_clustering_kmeans.R` (estandarización, $K^*$ por silueta, perfiles, sensibilidad PCA/PAM/AGNES/GMM y gráficos `output/figures/kmeans_*.png`).
* [**`05_flujo_delitos_ingesta_procesamiento.pdf`**](metodologia/instrucciones_codigo/05_flujo_delitos_ingesta_procesamiento.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/05_flujo_delitos_ingesta_procesamiento.qmd)): Explica `descarga_delitos_sdscj.R` y `procesamiento_delitos.R` (geometría GeoJSON oficial y panel anual de hurtos).
* [**`06_flujo_noticias_scraping_procesamiento.pdf`**](metodologia/instrucciones_codigo/06_flujo_noticias_scraping_procesamiento.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/06_flujo_noticias_scraping_procesamiento.qmd)): Explica `scraping_google_news.R` y `procesamiento_noticias.R` (Google News RSS, desambiguación, limpieza NLP y clasificador de 11 DAI).
* [**`07_flujo_sentometrics_elasticnet_shiny.pdf`**](metodologia/instrucciones_codigo/07_flujo_sentometrics_elasticnet_shiny.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/07_flujo_sentometrics_elasticnet_shiny.qmd)): Explica `03_analisis_sentometrics.R`, `06_descriptivos_corpus.R`, `05_export_insumos_shiny.R` y `master.R` (corpus objetivo de `993` noticias y `6` *features*, léxicos, `36` series, Elastic Net sobre `SIEDCO.csv`, `sentometrics_pipeline.rds`, atribuciones, figuras descriptivas y empaquetado Shiny).

```bash
# Ejemplo para compilar un cuaderno de instrucciones_codigo y mover el PDF a instrucciones_codigo/:
quarto render notebook/metodologia/instrucciones_codigo/qmd/07_flujo_sentometrics_elasticnet_shiny.qmd --to pdf
mv notebook/metodologia/instrucciones_codigo/qmd/07_flujo_sentometrics_elasticnet_shiny.pdf \
   notebook/metodologia/instrucciones_codigo/07_flujo_sentometrics_elasticnet_shiny.pdf
```
Los bloques de código explicados en `instrucciones_codigo/` son estáticos (resaltados con numeración fiel al script original) para permitir lectura sin ejecutar el pipeline completo.

---

> ⬅️ Volver al [README principal](../README.md) | Ir al [índice de scripts](../scripts/README.md)
