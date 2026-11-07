# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022–2026)
# SCRIPT: scripts/06_descriptivos_corpus.R
# ROL: Estadísticos descriptivos y visualizaciones del corpus (Tarea T-08)
# AUTORES: Olga Lucía Ramírez, Juan José Echeverry, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE:
#   - output/figures/figura3_noticias_por_anio.png
#   - output/figures/figura4_noticias_por_localidad.png
#   - output/figures/figura5_noticias_localidad_anio.png
#   - output/figures/figura6_longitud_noticias.png
#   - output/figures/figura7_tono_noticias_por_anio.png
#   - output/figures/figura8_corpus_summarize_documentos.png
#   - output/figures/figura9_corpus_summarize_features.png
#   - output/tables/tabla_descriptivos_corpus.csv
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
library(here)
library(conflicted)
library(arrow)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)
library(sentometrics)
library(lubridate)
library(readr)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas ----
ruta_proc <- here::here("data", "processed")
ruta_out  <- here::here("output")
ruta_fig  <- file.path(ruta_out, "figures")
ruta_tab  <- file.path(ruta_out, "tables")

if (!dir.exists(ruta_fig)) dir.create(ruta_fig, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(ruta_tab)) dir.create(ruta_tab, recursive = TRUE, showWarnings = FALSE)

# 2. Carga de Datos Procesados ----

## 2.1 Lectura del corpus de noticias y objeto sento_corpus ----
archivo_noticias <- file.path(ruta_proc, "03_noticias", "noticias_procesadas.parquet")
archivo_corpus   <- file.path(ruta_proc, "01_sento_corpus.rds")

noticias_df  <- arrow::read_parquet(archivo_noticias)
corpus_sento <- readRDS(archivo_corpus)

# 3. Estadísticas Descriptivas y Visualizaciones del Corpus ----

## 3.1 Número de noticias por año (corte septiembre 2026) ----
noticias_df <- noticias_df |>
  mutate(año = as.integer(año), mes = as.integer(mes)) |>
  filter(!(año == 2026 & mes > 9))

noticias_por_anio <- noticias_df |>
  group_by(año) |>
  summarise(conteo = n(), .groups = "drop")

p_fig3 <- ggplot(noticias_por_anio, aes(x = factor(año), y = conteo)) +
  geom_col(fill = "#1f77b4", width = 0.65) +
  geom_text(aes(label = scales::comma(conteo)), vjust = -0.4, size = 3.5) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(
    title    = "Volumen Anual de Noticias Analizadas en Bogotá (2022–2026)",
    subtitle = "Artículos de prensa digital recopilados por localidad",
    x        = "Año de publicación",
    y        = "Cantidad de noticias",
    caption  = "Fuente: Corpus procesado de Google News RSS."
  ) +
  theme_minimal(base_size = 11)

ggsave(
  filename = file.path(ruta_fig, "figura3_noticias_por_anio.png"),
  plot     = p_fig3,
  width    = 8,
  height   = 5,
  dpi      = 300
)

## 3.2 Número de noticias por localidad (barras horizontales) ----
noticias_por_localidad <- noticias_df |>
  group_by(localidad) |>
  summarise(conteo = n(), .groups = "drop") |>
  arrange(desc(conteo))

p_fig4 <- ggplot(noticias_por_localidad, aes(x = reorder(localidad, conteo), y = conteo)) +
  geom_col(fill = "#e67e22", width = 0.7) +
  coord_flip() +
  labs(
    title    = "Cobertura Mediática por Localidad Urbana de Bogotá",
    subtitle = "Total de artículos procesados entre 2022 y 2026",
    x        = "Localidad",
    y        = "Cantidad de noticias",
    caption  = "Fuente: Corpus procesado de Google News RSS."
  ) +
  theme_minimal(base_size = 11)

ggsave(
  filename = file.path(ruta_fig, "figura4_noticias_por_localidad.png"),
  plot     = p_fig4,
  width    = 9,
  height   = 7,
  dpi      = 300
)

## 3.3 Mapa de calor Localidad × Año ----
heatmap_df <- noticias_df |>
  group_by(localidad, año) |>
  summarise(conteo = n(), .groups = "drop")

p_fig5 <- ggplot(heatmap_df, aes(x = factor(año), y = reorder(localidad, conteo), fill = conteo)) +
  geom_tile(color = "white") +
  scale_fill_viridis_c(option = "plasma", name = "Nº noticias") +
  labs(
    title   = "Intensidad de Cobertura Periodística: Localidad × Año",
    x       = "Año",
    y       = "Localidad",
    caption = "Fuente: Corpus procesado de Google News RSS."
  ) +
  theme_minimal(base_size = 11)

ggsave(
  filename = file.path(ruta_fig, "figura5_noticias_localidad_anio.png"),
  plot     = p_fig5,
  width    = 10,
  height   = 9,
  dpi      = 300
)

## 3.4 Distribución de longitud léxica (número de palabras) ----
p_fig6 <- ggplot(noticias_df, aes(x = palabras_cuerpo)) +
  geom_histogram(binwidth = 50, fill = "#2980b9", color = "white") +
  labs(
    title   = "Distribución de la Extensión Léxica por Artículo",
    x       = "Número de palabras en el cuerpo limpio",
    y       = "Frecuencia de artículos",
    caption = "Fuente: Corpus procesado de Google News RSS."
  ) +
  theme_minimal(base_size = 11)

ggsave(
  filename = file.path(ruta_fig, "figura6_longitud_noticias.png"),
  plot     = p_fig6,
  width    = 8,
  height   = 5,
  dpi      = 300
)

## 3.5 Proporción de tono (sentimiento) por año ----
if ("sentimiento_categoria" %in% colnames(noticias_df)) {
  tono_por_anio <- noticias_df |>
    group_by(año, sentimiento_categoria) |>
    summarise(conteo = n(), .groups = "drop") |>
    group_by(año) |>
    mutate(pct = conteo / sum(conteo) * 100) |>
    ungroup()

  p_fig7 <- ggplot(tono_por_anio, aes(x = factor(año), y = pct, fill = sentimiento_categoria)) +
    geom_col(position = "dodge", width = 0.7) +
    scale_fill_manual(
      values = c("Negativo" = "#c0392b", "Neutro" = "#7f8c8d", "Positivo" = "#27ae60")
    ) +
    labs(
      title   = "Distribución Anual del Tono de las Noticias sobre Seguridad",
      x       = "Año",
      y       = "% de noticias",
      fill    = "Polaridad",
      caption = "Fuente: Cálculos con sentometrics (nrc_es + crimen_es)."
    ) +
    theme_minimal(base_size = 11)

  ggsave(
    filename = file.path(ruta_fig, "figura7_tono_noticias_por_anio.png"),
    plot     = p_fig7,
    width    = 9,
    height   = 5,
    dpi      = 300
  )
}

# 4. Tabla Descriptiva Resumen del Corpus ----

tabla_resumen <- noticias_df |>
  group_by(año) |>
  summarise(
    noticias         = n(),
    noticias_dai     = sum(es_dai_estricto, na.rm = TRUE),
    localidades      = n_distinct(localidad),
    media_palabras   = round(mean(palabras_cuerpo, na.rm = TRUE), 1),
    mediana_palabras = round(median(palabras_cuerpo, na.rm = TRUE), 1),
    sentimiento_prom = round(mean(sentimiento_score, na.rm = TRUE), 4),
    .groups = "drop"
  )

write_csv(tabla_resumen, file.path(ruta_tab, "tabla_descriptivos_corpus.csv"))

# 5. Diagnósticos S3 con sentometrics::corpus_summarize() (T-08) ----

## 5.1 Resumen mensual y anual del objeto sento_corpus ----
summary_mes  <- suppressWarnings(sentometrics::corpus_summarize(corpus_sento, by = "month"))
summary_anio <- suppressWarnings(sentometrics::corpus_summarize(corpus_sento, by = "year"))

if (!is.null(summary_mes$plots$doc_plot)) {
  ggsave(
    filename = file.path(ruta_fig, "figura8_corpus_summarize_documentos.png"),
    plot     = summary_mes$plots$doc_plot,
    width    = 9,
    height   = 5,
    dpi      = 300
  )
}

if (!is.null(summary_mes$plots$feature_plot)) {
  ggsave(
    filename = file.path(ruta_fig, "figura9_corpus_summarize_features.png"),
    plot     = summary_mes$plots$feature_plot,
    width    = 10,
    height   = 6,
    dpi      = 300
  )
}

message("✔ [T-08] Descriptivos del corpus y figuras corpus_summarize() generados en: ", ruta_fig)
message("✔ Tabla resumen exportada en: ", file.path(ruta_tab, "tabla_descriptivos_corpus.csv"))
