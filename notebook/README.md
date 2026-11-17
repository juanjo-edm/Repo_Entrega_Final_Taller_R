# Cuadernos Quarto (`notebook/`)

En esta carpeta se encuentran los cuadernos computacionales y documentos académicos del proyecto desarrollados en Quarto (`.qmd`), organizados en dos subcarpetas según su propósito:

```text
notebook/
├── README.md
├── entregas/
│   ├── 01_entrega_1_propuesta_eda.qmd                # Documento evaluativo de la Primera Entrega
│   ├── 01_entrega_1_propuesta_eda.html               # Versión web autocontenida
│   ├── 01_entrega_1_propuesta_eda.pdf                # Versión PDF de 3 páginas (Semana 11)
│   ├── 01_respuestas_evaluador_entrega_1.qmd         # Respuestas detalladas al evaluador (Entrega 1)
│   └── 01_respuestas_evaluador_entrega_1.pdf
└── metodologia/
    ├── 02_modelado_clustering_sentometrics.qmd       # Guía metodológica y pedagógica integral
    ├── 02_modelado_clustering_sentometrics.html      # Reporte interactivo con código y gráficos
    ├── 02_modelado_clustering_sentometrics.pdf
    ├── guia_estudio/
    │   ├── 05_guia_estudio_sustentacion.qmd          # Guía de estudio y banco de preguntas para sustentación
    │   └── 05_guia_estudio_sustentacion.pdf
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

## 1. Subcarpeta `notebook/entregas/`

Contiene los informes académicos preparados específicamente para cumplir con las rúbricas y límites formales de entrega del curso:

* [**`01_entrega_1_propuesta_eda.qmd`**](entregas/01_entrega_1_propuesta_eda.qmd):
  * **Hito evaluativo:** Primera Entrega (Propuesta de Trabajo Final y Análisis Exploratorio de Datos - EDA).
  * **Límite formal:** Máximo 3 páginas en formato PDF con márgenes académicos de 18mm y tablas LaTeX estandarizadas.
  * **Estructura del texto:**
    * Pregunta de investigación ($\le 150$ palabras).
    * Motivación ($\le 150$ palabras).
    * Descripción de los datos ($\le 150$ palabras).
    * Metodología y plan de manejo ($\le 150$ palabras).
    * Análisis preliminar y storytelling ($\le 700$ palabras, con tabla resumen sincronizada con el panel consolidado y dos figuras analíticas autocontenidas).
* [**`01_respuestas_evaluador_entrega_1.qmd`**](entregas/01_respuestas_evaluador_entrega_1.qmd) ([PDF](entregas/01_respuestas_evaluador_entrega_1.pdf)): Síntesis técnica de ajustes y respuestas a las observaciones de la Primera Entrega.

### Cómo compilar la Entrega 1:
```bash
# Compilar a versión PDF académica (3 páginas exactas):
quarto render notebook/entregas/01_entrega_1_propuesta_eda.qmd --to pdf

# Compilar a versión HTML interactiva:
quarto render notebook/entregas/01_entrega_1_propuesta_eda.qmd --to html
```

---

## 2. Subcarpeta `notebook/metodologia/`

Aloja el cuaderno metodológico maestro, la guía de estudio para sustentación y las cinco guías didácticas de código que documentan el pipeline reproducible en R. Sigue de manera estricta los estándares de programación declarados en [`docs/guias/estandares_programacion.md`](../docs/guias/estandares_programacion.md).

### 2.1 Cuaderno metodológico integral

* [**`02_modelado_clustering_sentometrics.qmd`**](metodologia/02_modelado_clustering_sentometrics.qmd) ([HTML](metodologia/02_modelado_clustering_sentometrics.html) | [PDF](metodologia/02_modelado_clustering_sentometrics.pdf)):
  * **Objetivo:** Servir como manual de estudio y replicación paso a paso de toda la metodología, tomando los artefactos de `data/processed/` (`01_delitos/`, `02_poblacion/`, `03_noticias/` y los objetos `.rds` `01` a `08`) y las tablas de `output/tables/`.
  * **Secciones del cuaderno (0 a 7):**
    0. **Configuración inicial y arquitectura:** Entorno reproducible, contrato de insumos base y esquema general del pipeline.
    1. **Datos de partida (`#sec-datos`):** Curaduría de SIEDCO/SDSCJ, proyecciones SDS, Google News RSS, desambiguación geográfica y clasificación en las 11 categorías oficiales DAI.
    2. **Tasas delictivas por 100.000 habitantes (`#sec-tasas`):** Formulación matemática e intuición del sesgo de denominador por población flotante (2022–septiembre de 2026).
    3. **Agrupamiento espacial con $K$-Means (`#sec-kmeans`):** Estandarización Z-score, optimización Hartigan-Wong, criterio de Silueta ($K^* = 3$, silueta media $0,5416$), sensibilidad multiescalar/Tidymodels (PCA, PAM, AGNES, GMM) y perfiles (*Céntrico e Institucional*, *Comercial y Automotor*, *Residencial y Periférico*).
    4. **Diagnóstico del corpus y análisis de sentimiento con `sentometrics` (`#sec-sentometrics`):** Descriptivos del corpus (Figuras 3–10, incluyendo facetas legibles mediante `facet_wrap()` en la Figura 10), 26 *features* binarias sin guiones medios, diccionarios (`nrc_es`, `crimen_es`) con modificadores de valencia ($t \in \{1,2,3,4\}$), agregación en tres niveles ($\omega$ `proportionalPol`, $\theta$ `proportional`, $b$ con ventana móvil de 6 meses y 7 curvas de memoria = 364 series) y extracción de extremos (`peakdocs()`, `peakdates()`).
    5. **Modelado econométrico supervisado (Elastic Net) y `attributions()` (`#sec-elasticnet`):** Mensualización empírica de $y_t$ con `prop_mensual_dai`, estimación regularizada calibrada por $\text{BIC}$ ($h = 1$ mes, $\alpha^* = 0,2$) y descomposición aditiva de atribuciones.
    6. **Cartografía espacial desagregada e integración para R Shiny (`#sec-mapa`):** Mapas `{sf}` desagregados por modalidad de hurto, conteo y tono mediático, además del mapa de consumo hacia `datos_consolidados_shiny.rds`.
    7. **Verificación de consistencia y conclusiones (`#sec-conclusiones`):** Auditoría de integridad sobre los objetos calculados en memoria y síntesis final.

### Cómo compilar el cuaderno de metodología:
```bash
quarto render notebook/metodologia/02_modelado_clustering_sentometrics.qmd --to html
quarto render notebook/metodologia/02_modelado_clustering_sentometrics.qmd --to pdf
```

---

## 3. Subcarpeta `notebook/metodologia/guia_estudio/`

* [**`05_guia_estudio_sustentacion.qmd`**](metodologia/guia_estudio/05_guia_estudio_sustentacion.qmd) ([PDF](metodologia/guia_estudio/05_guia_estudio_sustentacion.pdf)): Resumen compacto con fórmulas clave, cifras de control y banco de preguntas para la preparación de la sustentación oral.

```bash
quarto render notebook/metodologia/guia_estudio/05_guia_estudio_sustentacion.qmd --to pdf
```

---

## 4. Subcarpeta `notebook/metodologia/instrucciones_codigo/` (`03` a `07`)

Cada cuaderno se compila en PDF con diseño a doble columna (código exacto numerado a la izquierda y explicación línea por línea a la derecha, junto con diagramas de flujo TikZ). Los `.qmd` fuente están en [`metodologia/instrucciones_codigo/qmd/`](metodologia/instrucciones_codigo/qmd/) y los PDFs compilados en [`metodologia/instrucciones_codigo/`](metodologia/instrucciones_codigo/):

* [**`03_ingesta_tasas_poblacion.pdf`**](metodologia/instrucciones_codigo/03_ingesta_tasas_poblacion.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/03_ingesta_tasas_poblacion.qmd)): Explica `descarga_poblacion_sds.R` y `procesamiento_poblacion.R` (proyecciones SDS y tasas por 100.000 habitantes).
* [**`04_modelo_kmeans_clusters.pdf`**](metodologia/instrucciones_codigo/04_modelo_kmeans_clusters.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/04_modelo_kmeans_clusters.qmd)): Explica `04_clustering_kmeans.R` (estandarización, $K^*$ por silueta, perfiles, sensibilidad PCA/PAM/AGNES/GMM y gráficos `output/figures/kmeans_*.png`).
* [**`05_flujo_delitos_ingesta_procesamiento.pdf`**](metodologia/instrucciones_codigo/05_flujo_delitos_ingesta_procesamiento.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/05_flujo_delitos_ingesta_procesamiento.qmd)): Explica `descarga_delitos_sdscj.R` y `procesamiento_delitos.R` (geometría GeoJSON oficial y panel anual de hurtos).
* [**`06_flujo_noticias_scraping_procesamiento.pdf`**](metodologia/instrucciones_codigo/06_flujo_noticias_scraping_procesamiento.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/06_flujo_noticias_scraping_procesamiento.qmd)): Explica `scraping_google_news.R` y `procesamiento_noticias.R` (Google News RSS, desambiguación, limpieza NLP y clasificador de 11 DAI).
* [**`07_flujo_sentometrics_elasticnet_shiny.pdf`**](metodologia/instrucciones_codigo/07_flujo_sentometrics_elasticnet_shiny.pdf) ([`.qmd`](metodologia/instrucciones_codigo/qmd/07_flujo_sentometrics_elasticnet_shiny.qmd)): Explica `03_analisis_sentometrics.R`, `06_descriptivos_corpus.R`, `05_export_insumos_shiny.R` y `master.R` (corpus con 26 *features*, léxicos, 364 series, Elastic Net, atribuciones, figuras descriptivas y empaquetado Shiny).

```bash
# Ejemplo para compilar un cuaderno de instrucciones_codigo y mover el PDF a instrucciones_codigo/:
quarto render notebook/metodologia/instrucciones_codigo/qmd/07_flujo_sentometrics_elasticnet_shiny.qmd --to pdf
mv notebook/metodologia/instrucciones_codigo/qmd/07_flujo_sentometrics_elasticnet_shiny.pdf \
   notebook/metodologia/instrucciones_codigo/07_flujo_sentometrics_elasticnet_shiny.pdf
```
Los bloques de código explicados en `instrucciones_codigo/` son estáticos (resaltados con numeración fiel al script original) para permitir lectura sin ejecutar el pipeline completo.

---

> ⬅️ Volver al [README principal](../README.md) | Ir al [índice de scripts](../scripts/README.md)
