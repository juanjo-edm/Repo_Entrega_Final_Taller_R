# Estándares de Programación y Guía de Estilo

**Proyecto:** Hurtos y sentimiento mediático en Bogotá  
**Programa:** Maestría en Economía Aplicada (MECA) — *Taller de Programación en R*  
**Integrantes:** Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)  

---

Esta guía define los estándares de programación, estilo Tidyverse y documentación para garantizar que todo el código sea legible para humanos, navegable en RStudio, trazable y **100% reproducible desde una sesión limpia**.

---

## 1. Estructura y Navegación con el Outline de RStudio (`----`)

RStudio detecta automáticamente cualquier comentario que termine con al menos cuatro guiones (`----`) y lo convierte en un índice interactivo de navegación (**Document Outline**).

* **Atajo para abrir el Outline en RStudio:**
  * **macOS:** `Cmd + Shift + O`
  * **Windows / Linux:** `Ctrl + Shift + O`

### Niveles Jerárquicos de Secciones
Usamos numeración explícita y niveles de `#` para que el índice muestre la jerarquía exacta del pipeline:

```r
# 1. Nombre de la Sección Principal ----
## 1.1 Nombre de la Subsección ----
### 1.1.1 Paso específico (cuando sea necesario) ----
```

---

## 2. Configuración Inicial Obligatoria

Todo el contexto global se declara una sola vez en la **Sección 1** al inicio del script o cuaderno. Nunca se cargan librerías ni se cambian opciones a mitad del código.

### 2.1 Desactivar Notación Científica y Fijar Semilla
```r
## 1.1 Opciones globales y semilla ----
rm(list = ls())
options(scipen = 999) # Desactiva la notación científica en salidas numéricas
set.seed(20261014)    # Garantiza reproducibilidad en procedimientos estocásticos
```

### 2.2 Declaración Explícita de Librerías y `{conflicted}`
```r
## 1.2 Instalación y carga de librerías ----
library(here)         # Rutas relativas desde la raíz del proyecto
library(conflicted)   # Gestión explícita de colisiones de nombres de funciones
library(arrow)        # Lectura y escritura en formato Apache Parquet
library(readr)        # Lectura y exportación de tablas planas (.csv)
library(dplyr)        # Verbos principales de manipulación y transformación
library(tidyr)        # Remodelado de datos (pivots, drop_na)
library(ggplot2)      # Visualización de datos
library(sentometrics) # Análisis de sentimiento cuantitativo
library(sf)           # Geometrías y datos espaciales

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
```

### 2.3 Rutas Reproducibles con `{here}`
* **Prohibido:** Usar `setwd()` o rutas absolutas locales (`/Users/...` o `C:/...`).
* **Regla:** Todas las rutas se construyen al inicio con `here::here()`:
```r
## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_raw      <- here::here("data", "raw")
ruta_datos_clean    <- here::here("data", "processed")
ruta_salida_tablas  <- here::here("output", "tables")
ruta_salida_figuras <- here::here("output", "figures")
```

---

## 3. Convenciones de Estilo Tidyverse (`r-tidyverse-style`)

1. **Nombres Descriptivos (`snake_case`):**
   * Usar exclusivamente minúsculas separadas por guion bajo (`_`).
   * Sustantivos para objetos y tablas (`hurtos_localidad_anual`, `sentimiento_noticias`).
   * Verbos para funciones propias (`calcular_tasas_hurto()`).
   * Evitar nombres opacos (`df`, `df2`, `temp`, `base_final`).
2. **Asignación, Espaciado y Longitud de Línea:**
   * Usar `<-` para asignar objetos y `=` para argumentos de funciones.
   * Colocar espacios alrededor de operadores binarios (`<-`, `==`, `+`, `-`, `~`) y después de comas.
   * Sangría de 2 espacios (sin tabuladores).
   * Límite de ~80 caracteres por línea.
3. **Uso del Pipe Nativo (`|>`):**
   * Estandarizamos el uso de `|>`. Colocar al final de la línea e indentar a 2 espacios.

---

## 4. Priorización de `dplyr` para Manipulación

Toda limpieza, filtrado, recodificación y agregación prioriza los verbos de `dplyr` sobre la indexación base (`df[df$x == 1, ]`):
* `filter()`, `mutate()`, `select()`, `group_by()`, `summarise()`, `arrange()`, `left_join()`.

### Trazabilidad de Estados y Control de Auditoría
Cuando una transformación cambie la unidad de análisis o aplique filtros importantes, crea un estado numerado y valida programáticamente:
```r
## 3.1 Filtrado de localidades urbanas (excluye Sumapaz) ----
hurtos_02_urbano <- hurtos_01_raw |>
  filter(codigo_localidad != "20")

# Control de auditoría: verificar exactamente 19 localidades urbanas
stopifnot(length(unique(hurtos_02_urbano$codigo_localidad)) == 19)
```

---

## 5. Documentación en Tres Capas

1. **Antes del bloque:** Qué insumo entra, qué pregunta o paso metodológico resuelve y qué objeto produce.
2. **Dentro del código:** Razón de la decisión (por qué se elige una tasa por 100.000 habitantes, una ponderación o una ventana temporal).
3. **Después del bloque:** Validación programática (`stopifnot()`) o mensaje confirmatorio (`cli::cli_alert_success()`).

---

## 6. Checklist de Pre-Commit
Antes de hacer commit en Git:
- [ ] ¿El script / cuaderno corre de principio a fin desde sesión limpia (`Cmd + Shift + F10` y luego `source()` o `quarto render`)?
- [ ] ¿Todas las secciones nuevas usan `# X. ----` y `## X.Y ----` visibles en el Outline?
- [ ] ¿Se usó `snake_case`, asignación `<-` y pipe nativo `|>`?
- [ ] ¿Se respetó el uso de `{here}` evitando `setwd()` y rutas absolutas?
- [ ] ¿Los artefactos de salida se guardaron en `output/tables/` o `output/figures/`?
