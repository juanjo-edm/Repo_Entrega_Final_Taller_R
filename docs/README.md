# Documentación del Proyecto

Bienvenido al centro de documentación del proyecto de investigación sobre hurtos y percepción mediática en Bogotá (**Grupo 10 — Maestría en Economía Aplicada, Universidad de los Andes**).

Para facilitar la navegación y el mantenimiento del repositorio, los documentos están organizados en cinco subcarpetas temáticas:

```text
docs/
├── README.md                                 # Índice general de la documentación
│
├── enunciados/                               # Pautas oficiales y rúbricas del curso
│   ├── README.md                             # Resumen de entregables y ponderaciones
│   ├── enunciado_primera_entrega.md          # Pautas de la Primera Entrega (20 de octubre: 10%)
│   └── enunciado_entrega_final_y_presentacion.md # Pautas de presentación y entrega final (17 de noviembre: 30%)
│
├── proyecto/                                 # Definición conceptual y gestión del equipo
│   ├── README.md                             # Visión general de la investigación y sub-equipos
│   ├── propuesta_proyecto.md                 # Pregunta, hipótesis, datos, sentometrics y K-means
│   └── plan_de_trabajo.md                    # Sub-equipos, roles, cronograma al 17-Nov y flujo Git
│
├── sentometrics/                             # Literatura y referencias del paquete sentometrics
│   ├── README.md                             # Explicación del repositorio, web oficial y metodología
│   ├── paper_sentometrics_jss_2021.pdf       # Paper publicado en Journal of Statistical Software (JSS)
│   └── manual_referencia_sentometrics_cran.pdf # Manual técnico oficial de CRAN (versión 1.0.1)
│
├── guias/                                    # Estándares técnicos y buenas prácticas
│   ├── README.md                             # Principios de reproducibilidad del equipo
│   └── estandares_programacion.md            # Guía de estilo en R, Outline, here y control de errores
│
└── diccionario_datos/                        # Diccionario de datos y contratos del proyecto
    ├── README.md                             # Índice maestro, linaje, llaves PK/FK y diagrama ER
    ├── 01_datos_crudos.md                    # Capa cruda: SIEDCO.csv, GeoJSON, Parquet población y RSS
    ├── 02_tablas_procesadas.md               # Capa procesada: paneles mensuales/anuales, microdatos y clústeres
    ├── 03_artefactos_sentometrics_shiny.md   # Capa analítica: sentometrics_pipeline.rds y datos_consolidados_shiny.rds
    └── 04_tablas_salida.md                   # Capa de salida: tablas CSV resumen, sensibilidad y auditoría
```

---

## 📂 Contenido por Subcarpeta

### 1. [Enunciados y Rúbricas (`docs/enunciados/`)](enunciados/README.md)
Documentos emitidos por el equipo docente con las pautas y rúbricas oficiales de calificación:
* [**`enunciado_primera_entrega.md`**](enunciados/enunciado_primera_entrega.md): Requisitos de la Primera Entrega (20 de octubre de 2026, 10% de la nota), límites de palabras por sección y rúbrica detallada.
* [**`enunciado_entrega_final_y_presentacion.md`**](enunciados/enunciado_entrega_final_y_presentacion.md): Pautas de la Presentación en clase (15%) y del Documento Final + Script replicable + Shiny App (15%) para el 17 de noviembre de 2026.

---

### 2. [Proyecto y Planificación (`docs/proyecto/`)](proyecto/README.md)
Documentos de formulación teórica, metodológica y operativa del proyecto del Grupo 10:
* [**`propuesta_proyecto.md`**](proyecto/propuesta_proyecto.md): Marco conceptual, pregunta problema, justificación, fuentes de datos abiertos, modelo NLP con `sentometrics` y clustering con $K$-means.
* [**`plan_de_trabajo.md`**](proyecto/plan_de_trabajo.md): Conformación de los sub-equipos temáticos de 3 integrantes, facilitadores, cronograma con fechas límite hasta el cierre del 17 de noviembre y protocolo de ramas en Git.

---

### 3. [Documentación y Papers de `sentometrics` (`docs/sentometrics/`)](sentometrics/README.md)
Referencias bibliográficas y manuales técnicos del paquete econométrico de análisis de sentimiento:
* [**`paper_sentometrics_jss_2021.pdf`**](sentometrics/paper_sentometrics_jss_2021.pdf): Paper publicado en el *Journal of Statistical Software* (Ardia et al., 2021).
* [**`manual_referencia_sentometrics_cran.pdf`**](sentometrics/manual_referencia_sentometrics_cran.pdf): Manual de funciones oficial de CRAN (versión 1.0.1).
* [**`README.md`**](sentometrics/README.md): Explicación detallada del repositorio en GitHub ([`SentometricsResearch/sentometrics`](https://github.com/SentometricsResearch/sentometrics)), web oficial ([`sentometrics.com`](https://www.sentometrics.com/)) y aplicación a las localidades de Bogotá.

---

### 4. [Guías y Estándares (`docs/guias/`)](guias/README.md)
Guías técnicas para asegurar la calidad y reproducibilidad del código fuente:
* [**`estandares_programacion.md`**](guias/estandares_programacion.md): Guía de estilo MECA para R: Outline `----`, rutas relativas con `{here}`, gestión de conflictos con `{conflicted}`, pipe nativo `|>` y control de errores con `stopifnot()`.

---

### 5. [Diccionario de Datos y Contratos (`docs/diccionario_datos/`)](diccionario_datos/README.md)
Documentación exhaustiva de esquema, rangos, nulabilidad, llaves primarias (`PK`/`FK`) y linaje de extremo a extremo para todas las capas de datos del repositorio:
* [**`README.md`**](diccionario_datos/README.md): Índice maestro, arquitectura de 4 capas, diagrama entidad-relación y mapa de consumo.
* [**`01_datos_crudos.md`**](diccionario_datos/01_datos_crudos.md): Insumos crudos de SDSCJ (GeoJSON), SDS (Parquet) y Google News RSS.
* [**`02_tablas_procesadas.md`**](diccionario_datos/02_tablas_procesadas.md): Paneles limpios, corpus depurado, clústeres $K$-means y panel consolidado.
* [**`03_artefactos_sentometrics_shiny.md`**](diccionario_datos/03_artefactos_sentometrics_shiny.md): Objetos S3 `01`..`08 .rds` y bundle consolidado `datos_consolidados_shiny.rds`.
* [**`04_tablas_salida.md`**](diccionario_datos/04_tablas_salida.md): Tablas CSV exportadas en `output/tables/` (perfiles y sensibilidad K-Means, descriptivos y auditoría DAI).

---

> ⬅️ Volver al [README principal en la raíz del repositorio](../README.md).
