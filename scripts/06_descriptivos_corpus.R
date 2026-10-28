# ===============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022–2026)
# SCRIPT: scripts/06_descriptivos_corpus.R
# ROL: Estadísticos descriptivos y visualizaciones del corpus de noticias
# AUTORES: Lucía Ramírez
# PRODUCE: output/figures/figura3_noticias_por_anio.png,
#          output/figures/figura4_noticias_por_localidad.png,
#          output/figures/figura5_noticias_localidad_anio.png,
#          output/figures/figura6_longitud_noticias.png,
#          output/figures/figura7_tono_noticias_por_anio.png,
#          output/figures/figura8_corpus_summarize_documentos.png,
#          output/figures/figura9_corpus_summarize_features.png,
#          output/tables/tabla_descriptivos_corpus.csv
# ===============================================================================

# 1. Configuración y Dependencias -------------------------------------------------

## 1.1 Opciones globales y semilla ------------------------------------------------
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----------------------------------------------------------
# Usamos la biblioteca local donde instalamos los paquetes
.libPaths('C:/Users/olgal/OneDrive/Documentos/Olga/Maestría Economía Aplicada/R/Lucia_Final/R_libs')

library(here)
library(conflicted)
library(arrow)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(sentometrics)
library(lubridate)
library(readr)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas ------------------------------------------------------------
ruta_proc <- here::here("data", "processed")
ruta_out  <- here::here("output")
ruta_fig  <- file.path(ruta_out, "figures")
ruta_tab  <- file.path(ruta_out, "tables")

# crear carpetas si no existen
if (!dir.exists(ruta_fig)) dir.create(ruta_fig, recursive = TRUE)
if (!dir.exists(ruta_tab)) dir.create(ruta_tab, recursive = TRUE)

# 2. Carga de datos ---------------------------------------------------------------

## 2.1 Lectura del parquet ---------------------------------------------------------
archivo_noticias <- file.path(ruta_proc, "03_noticias", "noticias_procesadas.parquet")
noticias_df <- arrow::read_parquet(archivo_noticias)

# 3. Estadísticas descriptivas y visualizaciones -----------------------------------

## 3.1 Número de noticias por año (corte septiembre 2026) ------------------------
noticias_df <- noticias_df %>%
  mutate(año = as.integer(año), mes = as.integer(mes)) %>%
  filter(!(año == 2026 & mes > 9))

noticias_por_anio <- noticias_df %>%
  group_by(año) %>%
  summarise(conteo = n(), .groups = "drop")

ggplot(noticias_por_anio, aes(x = factor(año), y = conteo)) +
  geom_col(fill = "steelblue") +
  labs(title = "Número de noticias por año",
       x = "Año",
       y = "Cantidad de noticias",
       caption = "Fuente: datos procesados de noticias") +
  theme_minimal()

ggsave(filename = file.path(ruta_fig, "figura3_noticias_por_anio.png"), width = 8, height = 5, dpi = 300)

## 3.2 Número de noticias por localidad (barras horizontales) ----------------------
noticias_por_localidad <- noticias_df %>%
  group_by(localidad) %>%
  summarise(conteo = n(), .groups = "drop") %>%
  arrange(desc(conteo))

ggplot(noticias_por_localidad, aes(x = reorder(localidad, conteo), y = conteo)) +
  geom_col(fill = "darkorange") +
  coord_flip() +
  labs(title = "Número de noticias por localidad",
       x = "Localidad",
       y = "Cantidad de noticias",
       caption = "Fuente: datos procesados de noticias") +
  theme_minimal()

ggsave(filename = file.path(ruta_fig, "figura4_noticias_por_localidad.png"), width = 9, height = 7, dpi = 300)

## 3.3 Mapa de calor localidad × año ----------------------------------------------
heatmap_df <- noticias_df %>%
  group_by(localidad, año) %>%
  summarise(conteo = n(), .groups = "drop")

ggplot(heatmap_df, aes(x = factor(año), y = reorder(localidad, conteo), fill = conteo)) +
  geom_tile(color = "white") +
  scale_fill_viridis_c(option = "plasma", name = "Nº noticias") +
  labs(title = "Mapa de calor: Localidad × Año",
       x = "Año",
       y = "Localidad",
       caption = "Fuente: datos procesados de noticias") +
  theme_minimal()

ggsave(filename = file.path(ruta_fig, "figura5_noticias_localidad_anio.png"), width = 10, height = 9, dpi = 300)

## 3.4 Distribución de longitud (número de palabras) -------------------------------
ggplot(noticias_df, aes(x = palabras_cuerpo)) +
  geom_histogram(binwidth = 50, fill = "steelblue", color = "white") +
  labs(title = "Distribución del número de palabras por noticia",
       x = "Número de palabras",
       y = "Frecuencia",
       caption = "Fuente: datos procesados de noticias") +
  theme_minimal()

ggsave(filename = file.path(ruta_fig, "figura6_longitud_noticias.png"), width = 8, height = 5, dpi = 300)

## 3.5 Proporción de tono (sentimiento) por año ------------------------------------
if ("sentimiento_categoria" %in% colnames(noticias_df)) {
  tono_por_anio <- noticias_df %>%
    group_by(año, sentimiento_categoria) %>%
    summarise(conteo = n(), .groups = "drop") %>%
    group_by(año) %>%
    mutate(pct = conteo / sum(conteo) * 100)
  
  ggplot(tono_por_anio, aes(x = factor(año), y = pct, fill = sentimiento_categoria)) +
    geom_col(position = "dodge") +
    labs(title = "Proporción de tono de noticias por año",
         x = "Año",
         y = "% de noticias",
         fill = "Sentimiento",
         caption = "Fuente: datos procesados de noticias") +
    theme_minimal()
  
  ggsave(filename = file.path(ruta_fig, "figura7_tono_noticias_por_anio.png"), width = 9, height = 5, dpi = 300)
}

# 4. Tabla resumen ---------------------------------------------------------------

tabla_resumen <- noticias_df %>%
  group_by(año) %>%
  summarise(
    noticias = n(),
    localidades = n_distinct(localidad),
    media_palabras = mean(palabras_cuerpo, na.rm = TRUE),
    mediana_palabras = median(palabras_cuerpo, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(tabla_resumen, file.path(ruta_tab, "tabla_descriptivos_corpus.csv"))

# 5. Sentometrics ---------------------------------------------------------------

## 5.1 Preparar sento_corpus ------------------------------------------------------
# columnas requeridas: id, date, texts + binarias por localidad

sento_df <- noticias_df %>%
  mutate(
    id = paste0("doc_", row_number()),
    date = as.Date(fecha),
    texts = paste(titulo, ifelse(is.na(resumen), "", resumen), sep = ". ")
  )

# crear variables binarias por localidad (sin tildes, sin espacios, con guiones bajos)
localidades_vec <- unique(sento_df$localidad)

normalizar <- function(x) {
  x %>%
    str_to_lower() %>%
    str_replace_all("[áÁ]", "a") %>%
    str_replace_all("[éÉ]", "e") %>%
    str_replace_all("[íÍ]", "i") %>%
    str_replace_all("[óÓ]", "o") %>%
    str_replace_all("[úÚ]", "u") %>%
    str_replace_all("[ñÑ]", "n") %>%
    str_replace_all("[\\s-]+", "_") %>%
    str_replace_all("[^a-z0-9_]+", "")
}

for (loc in localidades_vec) {
  col_name <- normalizar(loc)
  sento_df[[col_name]] <- ifelse(sento_df$localidad == loc, 1L, 0L)
}

# conservar solo columnas relevantes para sentometrics
sento_corpus_df <- sento_df %>%
  select(id, date, texts, any_of(sapply(localidades_vec, normalizar)))

corpus_sento <- sentometrics::sento_corpus(corpusdf = as.data.frame(sento_corpus_df), do.clean = FALSE)

## 5.2 corpus_summarize ----------------------------------------------------------
summary_obj <- sentometrics::corpus_summarize(corpus_sento, by = "year")

# Guardar los gráficos que produce corpus_summarize
if (!is.null(summary_obj$plots$documentos)) {
  ggsave(filename = file.path(ruta_fig, "figura8_corpus_summarize_documentos.png"),
         plot = summary_obj$plots$documentos, width = 9, height = 5, dpi = 300)
}
if (!is.null(summary_obj$plots$features)) {
  ggsave(filename = file.path(ruta_fig, "figura9_corpus_summarize_features.png"),
         plot = summary_obj$plots$features, width = 9, height = 5, dpi = 300)
}

# 6. Mensaje final ---------------------------------------------------------------
message("✔ Archivos generados:")
message(" - Figuras en ", ruta_fig)
message(" - Tabla en ", file.path(ruta_tab, "tabla_descriptivos_corpus.csv"))
