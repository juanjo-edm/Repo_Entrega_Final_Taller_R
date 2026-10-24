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
    ├── 02_modelado_clustering_sentometrics.qmd   # Cuaderno metodológico integral de modelado
    └── 02_modelado_clustering_sentometrics.html  # Reporte interactivo con código y gráficos
```

---

## 1. Subcarpeta `notebook/entregas/`

Contiene los informes académicos preparados específicamente para cumplir con las rúbricas y límites formales de entrega del curso:

* [**`01_entrega_1_propuesta_eda.qmd`**](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/notebook/entregas/01_entrega_1_propuesta_eda.qmd):
  * **Hito evaluativo:** Primera Entrega (Propuesta de Trabajo Final y Análisis Exploratorio de Datos - EDA).
  * **Límite formal:** Máximo 3 páginas en formato PDF con márgenes académicos de 18mm y tablas LaTeX estandarizadas.
  * **Estructura del texto:**
    * Pregunta de investigación ($\le 150$ palabras).
    * Motivación ($\le 150$ palabras).
    * Descripción de los datos ($\le 150$ palabras).
    * Metodología y plan de manejo ($\le 150$ palabras).
    * Análisis preliminar y storytelling ($\le 700$ palabras, con tabla resumen y dos figuras analíticas autocontenidas).

### Cómo compilar la Entrega 1:
```bash
# Compilar a versión PDF académica (3 páginas exactas):
quarto render notebook/entregas/01_entrega_1_propuesta_eda.qmd --to pdf

# Compilar a versión HTML interactiva:
quarto render notebook/entregas/01_entrega_1_propuesta_eda.qmd --to html
```

---

## 2. Subcarpeta `notebook/metodologia/`

Aloja los cuadernos técnicos de experimentación econométrica, minería de texto y modelado estadístico que sustentan el proyecto. Estos cuadernos siguen de manera estricta los estándares de programación declarados en [`docs/guias/estandares_programacion.md`](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/docs/guias/estandares_programacion.md).

* [**`02_modelado_clustering_sentometrics.qmd`**](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/notebook/metodologia/02_modelado_clustering_sentometrics.qmd):
  * **Objetivo:** Tomar las bases limpias de `data/processed/hurtos/` y `data/processed/noticias/` para estimar los modelos del proyecto.
  * **Componentes del análisis:**
    1. **Tasas delictivas por 100.000 habitantes:** Análisis comparativo de hurto a personas, residencias y motocicletas para las 19 localidades urbanas (2022–2026).
    2. **Agrupamiento territorial ($K$-Means):** Diagnóstico matemático del número óptimo de clústeres mediante silueta promedio ($K^* = 3$, silueta $0.5416$) y caracterización de perfiles territoriales (*Céntrico e Institucional*, *Comercial y Automotor*, *Residencial y Periférico*).
    3. **Análisis cuantitativo de sentimiento (`sentometrics`):** Construcción del corpus estructurado (`sento_corpus`) con variables contextuales de clúster, integración de léxico NRC adaptado al español (`sento_lexicons`) y agregación temporal mensual con decaimiento exponencial (`sento_measures`).
    4. **Modelado econométrico supervisado:** Regresión penalizada Elastic Net (`sento_model`) con regularización BIC y descomposición de atribuciones temporales y léxicas (`attributions`).

### Cómo compilar el cuaderno de metodología:
```bash
# Compilar a reporte HTML interactivo autocontenido (con código plegable y figuras de alta resolución):
quarto render notebook/metodologia/02_modelado_clustering_sentometrics.qmd --to html
```
