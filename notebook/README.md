# Cuadernos Académicos Quarto

Esta carpeta contiene los documentos académicos interactivos desarrollados en Quarto (`.qmd`) para las entregas evaluativas del curso.

---

## Documentos

* [**`01_entrega_1_propuesta_eda.qmd`**](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/notebook/01_entrega_1_propuesta_eda.qmd):
  * **Hito:** Primera Entrega — Propuesta de Trabajo Final y Análisis Exploratorio de Datos (EDA).
  * **Ponderación:** 10% (Semana 11).
  * **Límite de páginas:** Máximo 3 páginas en PDF.
  * **Restricciones de palabras:**
    * Pregunta de investigación: $\le 150$ palabras.
    * Motivación: $\le 150$ palabras.
    * Descripción de los datos: $\le 150$ palabras.
    * Metodología / Plan de manejo: $\le 150$ palabras.
    * Análisis preliminar de datos y storytelling: $\le 700$ palabras (incluye estadísticas calculadas y al menos 2 gráficos autocontenidos).

---

## Cómo Compilar los Documentos

Desde la terminal en la raíz del proyecto:
```bash
# Compilación a PDF (formato académico de 3 páginas)
quarto render notebook/01_entrega_1_propuesta_eda.qmd --to pdf

# Compilación a HTML interactivo
quarto render notebook/01_entrega_1_propuesta_eda.qmd --to html
```

O en RStudio abriendo el archivo `.qmd` y haciendo clic en **Render** (`Cmd + Shift + K`).
