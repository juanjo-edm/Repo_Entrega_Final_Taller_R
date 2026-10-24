# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# SCRIPT: scripts/03_analisis_sentometrics.R
# ROL: Análisis Cuantitativo de Sentimiento con sentometrics y Fusión de Panel
# ==============================================================================

options(scipen = 999)
set.seed(20261014)

library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(syuzhet)
library(sentometrics)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

ruta_proc <- here::here("data", "processed")

# 1. Carga de Noticias Procesadas ----
archivo_noticias <- file.path(ruta_proc, "noticias", "noticias_procesadas.parquet")
df_noticias <- arrow::read_parquet(archivo_noticias)

# 2. Configuración del Léxico NRC en Español ----
nrc_es_crudo <- syuzhet::get_sentiment_dictionary("nrc", language = "spanish")
nrc_polaridad <- nrc_es_crudo |>
  filter(sentiment %in% c("positive", "negative")) |>
  mutate(score = ifelse(sentiment == "positive", 1, -1)) |>
  group_by(word) |>
  summarise(score = mean(score), .groups = "drop")

lex_df <- as.data.frame(nrc_polaridad[, c("word", "score")])
lex_sento <- sento_lexicons(list(nrc_val = lex_df))

# 3. Preparación de Corpus para sentometrics ----
df_noticias_sento <- df_noticias |>
  mutate(
    id = paste0("doc_", row_number()),
    date = as.Date(fecha),
    texts = paste(titulo, ifelse(is.na(resumen), "", resumen), sep = ". ")
  ) |>
  select(id, date, texts)

corpus_sento <- sento_corpus(
  corpusdf = as.data.frame(df_noticias_sento),
  do.clean = FALSE
)

# Cómputo de sentimiento proporcional (por palabra)
sentimiento_raw <- compute_sentiment(
  corpus_sento,
  lex_sento,
  how = "proportional"
)

# Extraer el puntaje de sentimiento neto por documento
df_sent_valores <- as.data.frame(sentimiento_raw)
df_sent_limpio <- tibble(
  id = df_sent_valores$id,
  date = df_sent_valores$date,
  word_count = df_sent_valores$word_count,
  sentimiento_score = df_sent_valores[[4]]
)

df_noticias_enriquecida <- df_noticias |>
  mutate(id = paste0("doc_", row_number())) |>
  left_join(df_sent_limpio |> select(id, word_count, sentimiento_score), by = "id") |>
  mutate(
    sentimiento_categoria = case_when(
      sentimiento_score < 0 ~ "Negativo",
      sentimiento_score > 0 ~ "Positivo",
      TRUE ~ "Neutro"
    )
  )

archivo_noticias_sent <- file.path(ruta_proc, "noticias", "noticias_con_sentimiento.parquet")
arrow::write_parquet(df_noticias_enriquecida, archivo_noticias_sent)
message("✔ Noticias con sentimiento guardadas en: ", archivo_noticias_sent)

# 4. Agregación de Sentimiento por Localidad y Año (2022-2026) ----
noticias_agg <- df_noticias_enriquecida |>
  filter(año >= 2022 & año <= 2026) |>
  group_by(localidad, año) |>
  summarise(
    noticias_conteo      = n(),
    sentimiento_promedio = round(mean(sentimiento_score, na.rm = TRUE), 4),
    sentimiento_mediana  = round(median(sentimiento_score, na.rm = TRUE), 4),
    prop_negativas       = round(mean(sentimiento_categoria == "Negativo", na.rm = TRUE) * 100, 2),
    prop_positivas       = round(mean(sentimiento_categoria == "Positivo", na.rm = TRUE) * 100, 2),
    prop_neutras         = round(mean(sentimiento_categoria == "Neutro", na.rm = TRUE) * 100, 2),
    .groups = "drop"
  )

# 5. Integración con el Panel Delictivo ----
panel_delitos <- arrow::read_parquet(file.path(ruta_proc, "panel_delitos_poblacion_localidad.parquet"))

panel_consolidado <- panel_delitos |>
  left_join(noticias_agg, by = c("localidad", "año")) |>
  mutate(
    noticias_conteo      = replace_na(noticias_conteo, 0),
    sentimiento_promedio = replace_na(sentimiento_promedio, 0),
    prop_negativas       = replace_na(prop_negativas, 0),
    prop_positivas       = replace_na(prop_positivas, 0),
    prop_neutras         = replace_na(prop_neutras, 0)
  )

archivo_panel_final <- file.path(ruta_proc, "panel_consolidado_localidad_anual.parquet")
arrow::write_parquet(panel_consolidado, archivo_panel_final)
message("✔ Panel consolidado (delitos + población + sentometrics) guardado en: ", archivo_panel_final)
