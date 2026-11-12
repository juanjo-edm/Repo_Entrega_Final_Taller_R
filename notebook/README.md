# Cuadernos Quarto (`notebook/`)

En esta carpeta se encuentran los cuadernos computacionales y documentos académicos del proyecto desarrollados en Quarto (`.qmd`), organizados en dos subcarpetas según su propósito:

```text
notebook/
├── README.md
├── entregas/
│   ├── 01_entrega_1_propuesta_eda.qmd        # Documento evaluativo de la Primera Entrega
│   ├── 01_entrega_1_propuesta_eda.html       # Versión web autocontenida
│   └── 01_entrega_1_propuesta_eda.pdf        # Versión PDF de 3 páginas (Semana 11)
└── metodologia/
    ├── 02_modelado_clustering_sentometrics.qmd   # Guía metodológica y pedagógica integral
    └── 02_modelado_clustering_sentometrics.html  # Reporte interactivo con código y gráficos
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

### Cómo compilar la Entrega 1:
```bash
# Compilar a versión PDF académica (3 páginas exactas):
quarto render notebook/entregas/01_entrega_1_propuesta_eda.qmd --to pdf

# Compilar a versión HTML interactiva:
quarto render notebook/entregas/01_entrega_1_propuesta_eda.qmd --to html
```

---

## 2. Subcarpeta `notebook/metodologia/`

Aloja la guía técnica y pedagógica de minería de texto, agrupamiento no supervisado y modelado econométrico que sustenta el proyecto. Sigue de manera estricta los estándares de programación declarados en [`docs/guias/estandares_programacion.md`](../docs/guias/estandares_programacion.md).

* [**`02_modelado_clustering_sentometrics.qmd`**](metodologia/02_modelado_clustering_sentometrics.qmd):
  * **Objetivo:** Servir como manual de estudio paso a paso de toda la metodología, tomando los artefactos de `data/processed/` (`01_delitos/`, `02_poblacion/`, `03_noticias/` y los objetos `.rds` `01` a `08`) y las figuras de `output/figures/`.
  * **Secciones pedagógicas del cuaderno:**
    1. **Arquitectura del pipeline y curaduría de datos:** Diagrama Mermaid de extremo a extremo, desambiguación geográfica y clasificación en las 11 categorías oficiales de Delitos de Alto Impacto (DAI) de la SDSCJ.
    2. **Tasas delictivas por 100.000 habitantes y población flotante:** Formulación matemática e intuición económica del sesgo de denominador en localidades centrales y comerciales (2022–2026).
    3. **Agrupamiento espacial no supervisado ($K$-Means):** Estandarización Z-score, minimización de inercia intra-clúster $W(C)$ (Hartigan-Wong), validación por coeficiente de Silueta ($K^* = 3$, silueta media $0,542$) y perfilamiento de los 3 clústeres (*Céntrico e Institucional*, *Comercial y Automotor*, *Residencial y Periférico*).
    4. **Diagnóstico y estadísticas descriptivas del corpus (Tarea T-08):** Integración de las Figuras 3 a 9 (`06_descriptivos_corpus.R`), tabla anual resumen y diagnósticos de `sentometrics::corpus_summarize()`.
    5. **Modelado textual con `sentometrics`:** Las 26 *features* binarias, diccionarios duales (`nrc_es` y `crimen_es`), modificadores de valencia contextuales ($t \in \{1, 2, 3, 4\}$), agregación en tres niveles ($\omega$ `proportionalPol`, $\theta$ `proportional`, $b$ con 7 esquemas temporales en ventana de 6 meses = 364 series) y detección de extremos con `peakdocs()` / `peakdates()`.
    6. **Regresión regularizada Elastic Net (`sento_model`) y `attributions()`:** Mensualización empírica de $y_t$ con `prop_mensual_dai`, penalización mixta $\ell_1/\ell_2$ calibrada vía $\text{BIC}$ ($R^2 = 87,5\%$) y descomposición aditiva de atribuciones.
    7. **Integración espacial con `{sf}`:** Cartografía comparativa de clústeres y tasas de hurto en las 19 localidades urbanas.
    8. **Guía rápida de estudio y contrato de artefactos `.rds`:** Preguntas clave de sustentación y diccionario técnico de los objetos que alimentan la app Shiny.

### Cómo compilar el cuaderno de metodología:
```bash
# Compilar a reporte HTML interactivo autocontenido:
quarto render notebook/metodologia/02_modelado_clustering_sentometrics.qmd --to html
```
