# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Módulo 03 - Análisis Cuantitativo de Sentimiento con sentometrics
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
library(sentometrics)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_raw      <- here::here("data", "raw")
ruta_datos_clean    <- here::here("data", "processed")
ruta_salida_tablas  <- here::here("output", "tables")
ruta_salida_figuras <- here::here("output", "figures")

# 2. Conformación del Corpus Noticioso (sento_corpus) ----
# Lectura de noticias desde data/raw/, estructuración de fechas y atributos

# 3. Incorporación del Léxico NRC en Español (sento_lexicons) ----
# Configuración de categorías de polaridad positiva y negativa

# 4. Cómputo de Sentimiento Proporcional y Agregación ----
# compute_sentiment() a nivel noticia y consolidación por Localidad x Año

# 5. Exportación de Métricas de Sentimiento ----
# Guardado en data/processed/ (formato Parquet / RDS)
