# Guías Técnicas y Estándares de Programación

En esta carpeta se concentran las normas de desarrollo, pautas de reproducibilidad y estándares de estilo adoptados por el equipo para mantener un código limpio, navegable y reproducible.

---

## Documentos disponibles

| Archivo | Tema | Descripción |
| :--- | :--- | :--- |
| [**`estandares_programacion.md`**](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/docs/guias/estandares_programacion.md) | **Estilo y Reproducibilidad en R** | Reglas obligatorias de programación: organización con índice interactivo en RStudio (`----`), rutas relativas con `{here}`, resolución explícita de conflictos de nombres con `{conflicted}`, pipe nativo `|>`, estilo Tidyverse y validación temprana con `stopifnot()`. |

---

## Principios Fundamentales del Equipo

1. **Reproducibilidad limpia:** Ningún script debe contener `setwd()` ni rutas absolutas locales (`/Users/...` o `C:\...`).
2. **Navegabilidad:** Cada bloque de código cuenta con cabecera `# N. ----` visible en el Document Outline de RStudio (`Cmd + Shift + O`).
3. **Control de dependencias:** Carga estricta de librerías al inicio con control de conflictos.
4. **Validación de datos:** Pruebas defensivas para garantizar que no existan valores inesperados ni columnas faltantes en los pipelines.

---

> ⬅️ Volver al [índice de documentación](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/docs/README.md) | Volver al [README principal](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/README.md)
