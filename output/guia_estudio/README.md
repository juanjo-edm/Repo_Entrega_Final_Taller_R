# Centro de Estudio y Preparación para Sustentación (`output/guia_estudio/`)

Esta carpeta concentra el material de estudio y defensa técnica del **Grupo 3** (*Taller de Programación Aplicada a R · MECA Uniandes*) para tres hitos clave: la **co-evaluación al Grupo 1** (**miércoles 18 de noviembre, 6:25 p. m.**), la **exposición plenaria de 15 minutos** (**miércoles 25 de noviembre, 6:25 p. m.**, envío obligatorio **martes 24 nov, 7:30 p. m.**) y el **cierre definitivo de Semana 16** (`Documento Final + master.R + Bogo-Atrack`).

```text
output/guia_estudio/
├── README.md                                                     # Este índice y ruta de estudio por integrante
├── 01_metodologia_sustentacion/
│   ├── 01_guia_estudio_metodologia_sustentacion.qmd              # Fórmulas, sensibilidad, límites y 20 Q&A
│   └── 01_guia_estudio_metodologia_sustentacion.pdf
├── 02_presentacion_plenaria/
│   ├── 02_guia_estudio_presentacion_plenaria.qmd                 # Libreto de 15 min (6 integrantes) y rúbrica v2
│   └── 02_guia_estudio_presentacion_plenaria.pdf
├── 03_documento_final/
│   ├── 03_guia_estudio_documento_final.qmd                       # Anatomía del doc (4+1 págs.), rúbrica C1–C7 y cifras
│   └── 03_guia_estudio_documento_final.pdf
└── 04_aplicacion_shiny/
    ├── arquitectura_bogo_atrack_shiny.md                         # Arquitectura describe-design con diagramas Mermaid
    ├── 04_guia_estudio_bogo_atrack_shiny.qmd                     # Guía de las 6 pestañas, demo en 75 s y 8 Q&A técnicos
    └── 04_guia_estudio_bogo_atrack_shiny.pdf
```

---

## 1. Contenido de cada subcarpeta

| Subcarpeta | Documentos | Qué estudia y cuándo usar |
| :--- | :--- | :--- |
| [**`01_metodologia_sustentacion/`**](01_metodologia_sustentacion/) | [`01_guia_estudio_metodologia_sustentacion.pdf`](01_metodologia_sustentacion/01_guia_estudio_metodologia_sustentacion.pdf) ([`.qmd`](01_metodologia_sustentacion/01_guia_estudio_metodologia_sustentacion.qmd)) | Fórmulas exactas (`K-Means`, `proportionalPol`, `Elastic Net`), tablas de sensibilidad (`{recipes}`, `AGNES`, `PAM`, `GMM`), límites *in-sample* / causalidad, trazabilidad código ↔ modelo y **20 preguntas de defensa**. |
| [**`02_presentacion_plenaria/`**](02_presentacion_plenaria/) | [`02_guia_estudio_presentacion_plenaria.pdf`](02_presentacion_plenaria/02_guia_estudio_presentacion_plenaria.pdf) ([`.qmd`](02_presentacion_plenaria/02_guia_estudio_presentacion_plenaria.qmd)) | Reglas con penalización de la **Rúbrica v2**, libreto hablado minuto a minuto de los **6 integrantes (`2:30` c/u)** sobre las `10` diapositivas y recordatorio de co-evaluación al Grupo 1. |
| [**`03_documento_final/`**](03_documento_final/) | [`03_guia_estudio_documento_final.pdf`](03_documento_final/03_guia_estudio_documento_final.pdf) ([`.qmd`](03_documento_final/03_guia_estudio_documento_final.qmd)) | Mapa página por página de `documento_final_grupo_3.pdf` (`4` págs. cuerpo + `1` Anexo), checklist frente a criterios **`C1–C7`**, trazabilidad de Entrega 1 y tabla de consistencia numérica. |
| [**`04_aplicacion_shiny/`**](04_aplicacion_shiny/) | [`arquitectura_bogo_atrack_shiny.md`](04_aplicacion_shiny/arquitectura_bogo_atrack_shiny.md) · [`04_guia_estudio_bogo_atrack_shiny.pdf`](04_aplicacion_shiny/04_guia_estudio_bogo_atrack_shiny.pdf) ([`.qmd`](04_aplicacion_shiny/04_guia_estudio_bogo_atrack_shiny.qmd)) | Arquitectura técnica de `Bogo-Atrack` (diagramas Mermaid, reactivos con `bindCache()`, paleta ámbar vs. azul), guía de las `6` pestañas, demo cronometrado en `75 s` y `8` Q&A sobre `app/app.R`. |

---

## 2. Ruta recomendada de estudio por integrante (`Grupo 3`)

| Integrante | Turno en plenaria (`15 min`) | Documentos prioritarios para estudiar |
| :--- | :--- | :--- |
| **Miguelangel Palma** | `0:00 – 2:30` (Diapositivas `1–3`) | `02_presentacion_plenaria` (introducción, respuesta directa y `3` canales) + `03_documento_final` (Sección 1 y coherencia numérica). |
| **Gabriel Arturo Echeverry** | `2:30 – 5:00` (Diapositiva `4`) | `02_presentacion_plenaria` (fuentes SIEDCO, SDS, RSS, Sumapaz y filtro `993`) + `01_metodologia_sustentacion` (Sección 1 y Q&A #9, #10, #20). |
| **Juan Esteban Carvajal** | `5:00 – 7:30` (Diapositiva `5`) | `02_presentacion_plenaria` (tasas, población flotante y tono) + `01_metodologia_sustentacion` (Secciones 1 y 5, distinción `285,6` vs. `154,1`, Q&A #19). |
| **Sergio Alejandro López** | `7:30 – 10:00` (Diapositivas `6–7a`) | `01_metodologia_sustentacion` (Secciones 2–3, `Z-score`, sensibilidad `ARI = 1`, `proportionalPol`, `36` series, Q&A #1–#8, #15, #18). |
| **Olga Lucía Ramírez** | `10:00 – 12:30` (Diapositivas `7b–8`) | `01_metodologia_sustentacion` (Secciones 4–5, Elastic Net *in-sample*, motos periféricas, `r = +0,296 n.s.`, Q&A #11–#17) + `02_presentacion_plenaria`. |
| **Juan José Echeverry** | `12:30 – 15:00` (Diapositivas `9–10`) | `04_aplicacion_shiny` (libreto `75 s` y arquitectura `Bogo-Atrack`) + `03_documento_final` (trazabilidad Entrega 1 y `C7`) + `02_presentacion_plenaria`. |

---

## 3. Cómo recompilar los PDFs desde Quarto

Ejecutar desde la raíz del repositorio (`Repo_Entrega_Final_Taller_R/`):

```bash
quarto render output/guia_estudio/01_metodologia_sustentacion/01_guia_estudio_metodologia_sustentacion.qmd --to pdf
quarto render output/guia_estudio/02_presentacion_plenaria/02_guia_estudio_presentacion_plenaria.qmd --to pdf
quarto render output/guia_estudio/03_documento_final/03_guia_estudio_documento_final.qmd --to pdf
quarto render output/guia_estudio/04_aplicacion_shiny/04_guia_estudio_bogo_atrack_shiny.qmd --to pdf
```

> Entregables evaluativos oficiales y calendario de entregas en [`output/entregas/README.md`](../entregas/README.md).
