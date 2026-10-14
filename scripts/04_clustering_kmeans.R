# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Módulo 04 - Agrupamiento Territorial de Criminalidad con K-Means
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
library(cluster)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean    <- here::here("data", "processed")
ruta_salida_tablas  <- here::here("output", "tables")
ruta_salida_figuras <- here::here("output", "figures")

# 2. Preparación de Matriz de Tasas Estandarizadas ----
# Tasas de hurto a personas, residencias y motocicletas normalizadas

# 3. Diagnóstico de Número Óptimo de Clústeres (K = 2 a 4) ----
# Método de silueta y método del codo

# 4. Estimación de K-Means y Asignación de Perfiles ----
# Asignación de clúster a cada localidad

# 5. Exportación de Resultados ----
# Guardado en data/processed/ y tablas en output/tables/
