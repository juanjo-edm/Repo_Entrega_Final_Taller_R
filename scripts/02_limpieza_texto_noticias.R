# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediatico en Bogota (2022-2026)
# ARCHIVO: scripts/02_limpieza_texto_noticias.R
# ROL: Procesamiento, depuracion de texto y extraccion de metricas textuales
# AUTORES: Juan Jose Echeverry, Miguelangel Palma, Sergio Lopez (Grupo 10)
# PROGRAMA: Maestria en Economia Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# METODOLOGIA Y FLUJO SECUENCIAL:
# Este script constituye la segunda etapa (procesamiento y preparacion de texto)
# del analisis periodistico. Toma como insumo los microdatos crudos generados
# en la fase de ingesta (data/raw/noticias/), aplica filtros avanzados de
# desinfeccion de texto sobre el cuerpo editorial de las notas y exporta el
# dataset depurado hacia la carpeta de datos procesados (data/processed/noticias/).
#
# CRITERIOS DE LIMPIEZA TEXTUAL:
#   1. Neutralizacion de slogans institucionales y portadas genericas mediante
#      el uso fundamentado del resumen del hecho noticioso como respaldo.
#   2. Remocion de politicas de cookies, consentimientos de navegacion y encuestas.
#   3. Eliminacion de cuñas publicitarias, widgets multimedia y metadatos de audio IA.
#   4. Supresion de hipervinculos incrustados y normalizacion tipografica.
#   5. Construccion de variables auxiliares para mineria de texto y NLP
#      (longitud de palabras y campo unificado para analisis de sentimiento).
# ==============================================================================


# ------------------------------------------------------------------------------
# 1. ENTORNO DE TRABAJO, RESOLUCION DE CONFLICTOS Y LIBRERIAS
# ------------------------------------------------------------------------------

options(scipen = 999)
set.seed(20261014)

library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(stringi)
library(lubridate)

conflict_prefer("filter", "dplyr")
conflict_prefer("lag", "dplyr")
conflict_prefer("select", "dplyr")
conflict_prefer("duration", "lubridate")
conflict_prefer("guess_encoding", "readr")
conflict_prefer("timestamp", "utils")

# Definicion de rutas del proyecto
ruta_entrada_raw     <- here("data", "raw", "noticias", "noticias_google_news_consolidado.parquet")
ruta_salida_proc_dir <- here("data", "processed", "noticias")
archivo_salida_p     <- here("data", "processed", "noticias", "noticias_procesadas.parquet")
archivo_salida_r     <- here("data", "processed", "noticias", "noticias_procesadas.rds")

# Creacion del directorio de datos procesados si no existe
if (!dir.exists(ruta_salida_proc_dir)) {
  dir.create(ruta_salida_proc_dir, recursive = TRUE)
}


# ------------------------------------------------------------------------------
# 2. CARGA DE MICRODATOS CRUDOS DE PRENSA (DATA/RAW/NOTICIAS)
# ------------------------------------------------------------------------------

df_crudo <- read_parquet(ruta_entrada_raw)

# Garantizar unificacion de la variable fecha si el insumo crudo proviene de chunks
if (!"fecha" %in% colnames(df_crudo)) {
  df_crudo$fecha <- if ("fecha_iso" %in% colnames(df_crudo)) {
    if_else(!is.na(df_crudo$fecha_iso) & df_crudo$fecha_iso != "",
            as.Date(df_crudo$fecha_iso),
            as.Date(df_crudo$fecha_chunk_desde))
  } else {
    as.Date(df_crudo$fecha_chunk_desde)
  }
} else {
  df_crudo$fecha <- as.Date(df_crudo$fecha)
}


# ------------------------------------------------------------------------------
# 3. DEPURACION VECTORIZADA DEL CUERPO EDITORIAL DE LAS NOTICIAS
# ------------------------------------------------------------------------------

# Respaldo del texto crudo original para trazabilidad y auditoria
cuerpo_original <- df_crudo$cuerpo
resumen_base    <- df_crudo$resumen

# Etapa 3.1: Rescate por respaldo informativo (fallback)
# Si el cuerpo capturado corresponde al slogan institucional generico del portal
# o a repeticiones de avisos publicitarios, se sustituye por el resumen del hecho.
cuerpo_depurado <- if_else(
  str_detect(cuerpo_original, "Consulta aquí la información que te interesa sobre Bogotá|Publicidad Publicidad Publicidad|Puntos de venta Suscribirse a El Nuevo Siglo"),
  resumen_base,
  cuerpo_original
)

# Etapa 3.2: Remocion de advertencias de cookies y banners de navegacion
cuerpo_depurado <- if_else(
  grepl("cookies", cuerpo_depurado, ignore.case = TRUE) & nchar(cuerpo_depurado) < 500,
  resumen_base,
  cuerpo_depurado
)
cuerpo_depurado <- gsub("(?i)[^\n.]*\\bcookies\\b[^\n.]*\\.?", "", cuerpo_depurado, perl = TRUE)
cuerpo_depurado <- gsub("¿Cómo podemos ayudarte\\?.*", "", cuerpo_depurado)

# Etapa 3.3: Remocion de widgets multimedia, cuñas y firmas editoriales
cuerpo_depurado <- gsub("Audio generado con IA de Google [0-9]+:[0-9]+ / [0-9]+:[0-9]+", "", cuerpo_depurado)
cuerpo_depurado <- gsub("¡Comparte\\s+esta nota!.*", "", cuerpo_depurado)
cuerpo_depurado <- gsub("COPYRIGHT ©.*", "", cuerpo_depurado)
cuerpo_depurado <- gsub("(?i)(lea también|lea además|le puede interesar|vea también|siga leyendo|noticia en desarrollo)[^.]*\\.", "", cuerpo_depurado, perl = TRUE)
cuerpo_depurado <- gsub("(?i)(foto|crédito|video):\\s*[^.]*(\\.|\\n|$)", "", cuerpo_depurado, perl = TRUE)
cuerpo_depurado <- gsub("\\bPublicidad\\b", "", cuerpo_depurado)

# Etapa 3.4: Remocion de hipervinculos incrustados en el texto
cuerpo_depurado <- gsub("https?://\\S+|www\\.\\S+", "", cuerpo_depurado)

# Etapa 3.5: Normalizacion de caracteres especiales y colapso de espacios en blanco
cuerpo_depurado <- gsub("[\r\n\t\u00a0]+", " ", cuerpo_depurado)
cuerpo_depurado <- str_squish(cuerpo_depurado)

# Etapa 3.6: Control de longitud minima
# Si tras la depuracion el texto resultante queda vacio o menor a 40 caracteres,
# se preserva el resumen informativo como texto representativo de la nota.
cuerpo_depurado <- if_else(nchar(cuerpo_depurado) < 40 | is.na(cuerpo_depurado), resumen_base, cuerpo_depurado)
cuerpo_depurado <- str_squish(cuerpo_depurado)


# ------------------------------------------------------------------------------
# 4. EXTRACCION DE METRICAS TEXTUALES Y PREPARACION PARA NLP
# ------------------------------------------------------------------------------

df_procesado <- df_crudo |>
  mutate(
    # Reemplazo del cuerpo limpio
    cuerpo                  = cuerpo_depurado,
    
    # Metricas de volumen de texto para ponderacion econometrica
    caracteres_cuerpo       = nchar(cuerpo),
    palabras_cuerpo         = str_count(cuerpo, "\\S+"),
    palabras_titulo         = str_count(titulo, "\\S+"),
    
    # Campo integrado optimizado para mineria de texto y analisis de sentimiento
    texto_completo_nlp      = str_squish(paste(titulo, ".", cuerpo))
  ) |>
  # Remocion exhaustiva de todas las variables indicadoras logicas (booleanos)
  select(-where(is.logical)) |>
  # Remocion de parametros de consulta, fechas en texto y delimitadores de chunks
  select(
    -any_of(c(
      "consulta", "fecha_texto", "fecha_chunk_desde", "fecha_chunk_hasta",
      "fecha_iso", "pagina", "texto_corpus"
    ))
  ) |>
  # Ordenamiento logico y academico de las columnas finales
  select(
    fecha,
    año,
    mes,
    año_mes,
    trimestre,
    semana_año,
    localidad,
    confianza_geografica,
    fuente,
    tipo_medio,
    delito_alto_impacto,
    tipo_delito_dominante,
    titulo,
    resumen,
    cuerpo,
    texto_completo_nlp,
    palabras_titulo,
    palabras_cuerpo,
    caracteres_cuerpo,
    enlace
  ) |>
  arrange(localidad, fecha)


# ------------------------------------------------------------------------------
# 5. ALMACENAMIENTO PROCESADO (DATA/PROCESSED/NOTICIAS/)
# ------------------------------------------------------------------------------

# Guardado definitivo en formato columnar Parquet
write_parquet(df_procesado, archivo_salida_p)

# Guardado de respaldo en formato nativo serializado de R (.rds)
saveRDS(df_procesado, archivo_salida_r)


# ------------------------------------------------------------------------------
# 6. RESUMEN DESCRIPTIVO Y DIAGNOSTICO DE INTEGRIDAD DEL TEXTO
# ------------------------------------------------------------------------------

# Diagnostico de depuracion de caracteres
metricas_longitud <- data.frame(
  estadistico = c("minimo", "q1", "mediana", "media", "q3", "maximo"),
  caracteres_original = as.numeric(summary(nchar(cuerpo_original))),
  caracteres_limpio   = as.numeric(summary(nchar(cuerpo_depurado))),
  palabras_limpio     = as.numeric(summary(df_procesado$palabras_cuerpo))
)

# Cuadro de integridad y valores faltantes
valores_faltantes <- data.frame(
  variable = c("fecha", "titulo", "resumen", "cuerpo", "texto_completo_nlp", "delito_alto_impacto", "año_mes"),
  nulos    = c(
    sum(is.na(df_procesado$fecha)),
    sum(is.na(df_procesado$titulo)),
    sum(is.na(df_procesado$resumen)),
    sum(is.na(df_procesado$cuerpo)),
    sum(is.na(df_procesado$texto_completo_nlp)),
    sum(is.na(df_procesado$delito_alto_impacto)),
    sum(is.na(df_procesado$año_mes))
  )
)

print(metricas_longitud, row.names = FALSE)
print(valores_faltantes, row.names = FALSE)
