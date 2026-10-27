# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/03_analisis_sentometrics.R
# ROL: Análisis Cuantitativo de Sentimiento con sentometrics y Fusión de Panel
# PRODUCE: data/processed/panel_consolidado_localidad_anual.parquet
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
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

## 1.3 Rutas relativas ----
ruta_proc <- here::here("data", "processed")

# 2. Carga y Preparación del Corpus de Prensa ----

## 2.1 Carga del dataset de noticias procesadas ----
archivo_noticias <- file.path(ruta_proc, "03_noticias", "noticias_procesadas.parquet")
df_noticias <- arrow::read_parquet(archivo_noticias)

## 2.2 Preparación del formato sento_corpus ----
df_noticias_sento <- df_noticias |>
  mutate(
    id = paste0("doc_", row_number()),
    date = as.Date(fecha),
    texts = paste(titulo, ifelse(is.na(resumen), "", resumen), sep = ". ")
  ) |>
  select(id, date, texts)

corpus_sento <- sentometrics::sento_corpus(
  corpusdf = as.data.frame(df_noticias_sento),
  do.clean = FALSE
)

# 3. Configuración y Cómputo Léxico con sentometrics ----

## 3.1 Construcción del léxico de valencia NRC en español ----
nrc_es_crudo <- syuzhet::get_sentiment_dictionary("nrc", language = "spanish")
nrc_polaridad <- nrc_es_crudo |>
  filter(sentiment %in% c("positive", "negative")) |>
  mutate(score = ifelse(sentiment == "positive", 1, -1)) |>
  group_by(word) |>
  summarise(score = mean(score), .groups = "drop")

lex_df <- as.data.frame(nrc_polaridad[, c("word", "score")])
lex_sento <- sentometrics::sento_lexicons(list(nrc_val = lex_df))

## 3.2 Cómputo proporcional de polaridad por documento ----
sentimiento_raw <- sentometrics::compute_sentiment(
  corpus_sento,
  lex_sento,
  how = "proportional"
)

## 3.3 Clasificación categórica de sentimiento y exportación ----
df_sent_valores <- as.data.frame(sentimiento_raw)
df_sent_limpio <- tibble(
  id                = df_sent_valores$id,
  date              = df_sent_valores$date,
  word_count        = df_sent_valores$word_count,
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

arrow::write_parquet(df_noticias_enriquecida, archivo_noticias)
message("✔ Corpus de noticias enriquecido con sentimiento en: ", archivo_noticias)

# 4. Agregación de Métricas por Localidad y Año (2022–2026) ----

## 4.1 Resumen anual de sentimiento y proporciones de polaridad ----
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

# 5. Integración con el Panel Delictivo y Exportación ----

## 5.1 Fusión con tasas oficiales de hurto y población ----
panel_delitos <- arrow::read_parquet(file.path(ruta_proc, "02_poblacion", "panel_delitos_poblacion_localidad.parquet"))

panel_consolidado <- panel_delitos |>
  left_join(noticias_agg, by = c("localidad", "año")) |>
  mutate(
    noticias_conteo      = replace_na(noticias_conteo, 0),
    sentimiento_promedio = replace_na(sentimiento_promedio, 0),
    prop_negativas       = replace_na(prop_negativas, 0),
    prop_positivas       = replace_na(prop_positivas, 0),
    prop_neutras         = replace_na(prop_neutras, 0)
  )

## 5.2 Almacenamiento del panel consolidado final ----
archivo_panel_final <- file.path(ruta_proc, "panel_consolidado_localidad_anual.parquet")
arrow::write_parquet(panel_consolidado, archivo_panel_final)
message("✔ Panel consolidado (delitos + población + sentometrics) guardado en: ", archivo_panel_final)
