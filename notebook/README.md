# Cuadernos Quarto

En esta carpeta están los documentos académicos del proyecto desarrollados en Quarto (`.qmd`) para las entregas evaluativas del curso.

---

## Documento de la Primera Entrega

* [**`01_entrega_1_propuesta_eda.qmd`**](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/notebook/01_entrega_1_propuesta_eda.qmd):
  * **Hito:** Primera Entrega (Propuesta de Trabajo Final y Análisis Exploratorio de Datos - EDA).
  * **Ponderación:** 10% de la nota final (Semana 11).
  * **Límite de páginas:** Máximo 3 páginas en formato PDF.
  * **Límites de palabras por sección:**
    * Pregunta de investigación: máximo 150 palabras.
    * Motivación: máximo 150 palabras.
    * Descripción de los datos: máximo 150 palabras.
    * Metodología y plan de manejo: máximo 150 palabras.
    * Análisis preliminar de datos y storytelling: máximo 700 palabras (debe incluir estadísticas reales calculadas y al menos 2 gráficos autocontenidos).

---

## Cómo compilar el documento

Desde la terminal en la raíz del proyecto:

```bash
# Compilar a PDF (máximo 3 páginas con márgenes académicos de 20mm)
quarto render notebook/01_entrega_1_propuesta_eda.qmd --to pdf

# Compilar a versión HTML interactiva
quarto render notebook/01_entrega_1_propuesta_eda.qmd --to html
```

También puedes abrir el archivo `.qmd` en RStudio y presionar el botón **Render** (`Cmd + Shift + K`).
