# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Módulo 02 - Limpieza, Homologación Territorial y Cálculo de Tasas
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
rm(list = ls())
options(scipen = 999)
set.seed(20261014)

## 1.2 Instalación y carga de librerías ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_raw      <- here::here("data", "raw")
ruta_datos_clean    <- here::here("data", "processed")
ruta_salida_tablas  <- here::here("output", "tables")
ruta_salida_figuras <- here::here("output", "figures")

# 2. Homologación de Localidades y Limpieza de Caracteres ----
# Normalización de nombres de las 19 localidades urbanas

# 3. Filtrado de Delitos de Interés y Periodo 2022-2025 ----
# Hurtos a personas, residencias y motocicletas

# 4. Cálculo de Tasas por 100.000 Habitantes ----
# Fusión (join) con proyecciones poblacionales de la Secretaría de Salud

# 5. Exportación de Estados Procesados ----
# Guardado en data/processed/ (formato Parquet / RDS)
