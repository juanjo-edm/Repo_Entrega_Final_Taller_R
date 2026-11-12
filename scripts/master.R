# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/master.R
# ROL: Orquestador Maestro del Pipeline Reproducible de Punta a Punta
# AUTORES: Grupo 10 — Taller de Programación en R (MECA, Uniandes)
# ==============================================================================

# 1. Configuración Global ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librería de rutas relativas ----
library(here)

cat("======================================================================\n")
cat(" INICIANDO PIPELINE MAESTRO: HURTOS Y SENTOMETRICS EN BOGOTÁ (2022-2026)\n")
cat("======================================================================\n\n")

t_inicio <- Sys.time()

# 2. Etapa de Procesamiento de Datos Crudos a Limpios (Sub-equipo 1) ----

## 2.1 Procesamiento de delitos oficiales (SIEDCO / SDSCJ) ----
cat("[1/6] Procesando registros oficiales de delitos (SIEDCO / SDSCJ)...\n")
source(
  here::here("scripts", "02_procesamiento", "01_delitos", "procesamiento_delitos.R"),
  local = new.env()
)

## 2.2 Procesamiento demográfico y cálculo de tasas por 100k hab. (SDS) ----
cat("[2/6] Integrando proyecciones de población (SDS) y tasas por 100k hab...\n")
source(
  here::here("scripts", "02_procesamiento", "02_poblacion", "procesamiento_poblacion.R"),
  local = new.env()
)

## 2.3 Limpieza NLP del corpus de noticias y clasificación 11 DAI ----
cat("[3/6] Procesando corpus de prensa y clasificación oficial de 11 DAI...\n")
source(
  here::here("scripts", "02_procesamiento", "03_noticias", "procesamiento_noticias.R"),
  local = new.env()
)

# 3. Etapa de Modelado Territorial y NLP Sentometrics (Sub-equipo 2) ----

## 3.1 Agrupamiento espacial no supervisado K-Means (K* = 3) ----
cat("[4/6] Ejecutando agrupamiento territorial K-Means (K* = 3)...\n")
source(
  here::here("scripts", "04_clustering_kmeans.R"),
  local = new.env()
)

## 3.2 Pipeline cuantitativo de Sentometrics y modelo Elastic Net ----
cat("[5/6] Ejecutando pipeline completo de Sentometrics (01 a 08 .rds)...\n")
source(
  here::here("scripts", "03_analisis_sentometrics.R"),
  local = new.env()
)

## 3.3 Descriptivos del corpus (T-08) y empaquetado de insumos Shiny ----
cat("[6/6] Generando descriptivos del corpus (T-08) y bundle Shiny (.rds)...\n")
source(
  here::here("scripts", "06_descriptivos_corpus.R"),
  local = new.env()
)
source(
  here::here("scripts", "05_export_insumos_shiny.R"),
  local = new.env()
)

# Control de auditoría: verificar que el bundle consolidado de Shiny exista
stopifnot(file.exists(here::here("data", "processed", "datos_consolidados_shiny.rds")))

t_fin <- Sys.time()
duracion_seg <- round(as.numeric(difftime(t_fin, t_inicio, units = "secs")), 1)

cat("\n======================================================================\n")
cat(" ✔ PIPELINE COMPLETADO EXITOSAMENTE EN ", duracion_seg, " SEGUNDOS\n", sep = "")
cat(" • Para abrir el tablero Shiny: shiny::runApp(here::here('app'))\n")
cat("======================================================================\n")
