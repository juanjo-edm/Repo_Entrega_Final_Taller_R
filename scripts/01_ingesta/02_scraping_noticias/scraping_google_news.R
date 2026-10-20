# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediatico en Bogota (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R
# ROL: Ingesta, depuracion y consolidacion de prensa digital (Google News RSS)
# AUTORES: Juan Jose Echeverry, Miguelangel Palma, Sergio Lopez (Grupo 10)
# PROGRAMA: Maestria en Economia Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# METODOLOGIA:
# Este script ejecuta de manera secuencial y procedimental la captura,
# estandarizacion, deduplicacion y delimitacion temporal de notas de prensa
# sobre criminalidad y seguridad ciudadana en las 19 localidades urbanas de
# Bogota D.C. El diseno prescinde de funciones envolventes personalizadas para
# favorecer la trazabilidad y reproducibilidad del procesamiento econometrico.
# ==============================================================================

# 1. Entorno de trabajo, resolucion de conflictos y librerias ------------------

options(scipen = 999)
set.seed(20261014)

# Carga de paquetes
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(stringi)
library(lubridate)
library(xml2)
library(rvest)
library(httr)
library(jsonlite)

# Resolucion explicita de conflictos entre funciones
conflict_prefer("filter", "dplyr")
conflict_prefer("lag", "dplyr")
conflict_prefer("select", "dplyr")
conflict_prefer("duration", "lubridate")
conflict_prefer("guess_encoding", "readr")
conflict_prefer("timestamp", "utils")

# Rutas del proyecto
ruta_datos_raw      <- here("data", "raw")
ruta_noticias_raw   <- here("data", "raw", "noticias")
archivo_consolidado <- here("data", "raw", "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- here("data", "raw", "noticias_google_news_consolidado.rds")
archivo_cobertura   <- here("data", "raw", "noticias", "cobertura_historica.json")

if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE)
}

# Parametros muestrales
fecha_inicio_muestra  <- as.Date("2022-01-01")
fecha_fin_muestra     <- as.Date("2026-09-30")
ejecutar_descarga_rss <- FALSE


# 2. Catalogo de localidades y especificacion de consultas ---------------------

localidades_bogota <- c(
  "Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
  "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá",
  "Suba", "Barrios Unidos", "Teusaquillo", "Los Mártires",
  "Antonio Nariño", "Puente Aranda", "La Candelaria", 
  "Rafael Uribe Uribe", "Ciudad Bolívar"
)

terminos_delitos <- "(hurto OR robo OR atraco OR asalto OR inseguridad)"

df_consultas <- tibble(localidad = localidades_bogota) |>
  mutate(
    termino_localidad  = paste0('"', localidad, '"'),
    filtro_exclusiones = if_else(
      tolower(localidad) == "santa fe",
      "-futbol -liga -campin -dimayor -cardenal",
      ""
    ),
    cadena_busqueda    = str_squish(
      paste(terminos_delitos, "Bogota", termino_localidad, filtro_exclusiones)
    ),
    url_rss            = paste0(
      "https://news.google.com/rss/search?q=",
      URLencode(cadena_busqueda, reserved = TRUE),
      "&hl=es-419&gl=CO&ceid=CO:es-419"
    )
  )


# 3. Recoleccion de notas de prensa via Google News RSS ------------------------

if (isTRUE(ejecutar_descarga_rss)) {
  for (i in seq_len(nrow(df_consultas))) {
    loc_nombre <- df_consultas$localidad[i]
    url_actual <- df_consultas$url_rss[i]
    
    slug_loc <- tolower(stri_trans_general(loc_nombre, "Latin-ASCII"))
    slug_loc <- gsub("[^a-z0-9]", "_", slug_loc)
    archivo_chunk <- file.path(ruta_noticias_raw, paste0("chunk_rss_", slug_loc, ".parquet"))
    
    tryCatch({
      doc_xml    <- read_xml(url_actual)
      nodos_item <- xml_find_all(doc_xml, "//item")
      
      if (length(nodos_item) > 0) {
        titulos_raw <- xml_text(xml_find_first(nodos_item, "title"))
        enlaces_raw <- xml_text(xml_find_first(nodos_item, "link"))
        fechas_raw  <- xml_text(xml_find_first(nodos_item, "pubDate"))
        fuentes_raw <- xml_text(xml_find_first(nodos_item, "source"))
        desc_raw    <- xml_text(xml_find_first(nodos_item, "description"))
        
        resumenes_limpios <- character(length(desc_raw))
        for (k in seq_along(desc_raw)) {
          resumenes_limpios[k] <- tryCatch(
            read_html(desc_raw[k]) |> html_text(trim = TRUE),
            error = function(e) desc_raw[k]
          )
        }
        
        fechas_parseadas <- as.Date(parse_date_time(
          fechas_raw,
          orders = c("dmy HMS", "ymd HMS", "a d b Y HMS z", "a d b Y")
        ))
        
        enlaces_limpios <- sub("\\?(utm_|ref_|fbclid).*", "", enlaces_raw)
        
        df_chunk <- tibble(
          localidad         = loc_nombre,
          consulta          = df_consultas$cadena_busqueda[i],
          titulo            = titulos_raw,
          resumen           = resumenes_limpios,
          fuente            = fuentes_raw,
          fecha_texto       = fechas_raw,
          fecha_iso         = as.character(fechas_parseadas),
          enlace            = enlaces_limpios,
          fecha_chunk_desde = floor_date(fechas_parseadas, "month"),
          fecha_chunk_hasta = ceiling_date(fechas_parseadas, "month") - days(1),
          pagina            = 1L,
          cuerpo            = resumenes_limpios
        ) |>
          filter(!is.na(titulo) & titulo != "") |>
          filter(!is.na(enlace) & enlace != "") |>
          distinct(enlace, .keep_all = TRUE)
        
        write_parquet(df_chunk, archivo_chunk)
      }
    }, error = function(e) {
      warning(paste("Fallo en peticion para:", loc_nombre))
    })
    
    Sys.sleep(1.0)
  }
}


# 4. Consolidacion de registros historicos y particiones recientes -------------

df_historico_previo <- tibble()
if (file.exists(archivo_consolidado)) {
  df_historico_previo <- read_parquet(archivo_consolidado)
}

archivos_particiones <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)

lista_particiones <- vector("list", length(archivos_particiones))
for (j in seq_along(archivos_particiones)) {
  lista_particiones[[j]] <- tryCatch(
    read_parquet(archivos_particiones[j]),
    error = function(e) tibble()
  )
}
df_particiones <- bind_rows(lista_particiones)

df_unificado_bruto <- bind_rows(df_historico_previo, df_particiones)


# 5. Normalizacion, deduplicacion dual y delimitacion temporal ------------------

df_muestra_limpia <- df_unificado_bruto |>
  filter(!is.na(enlace) & enlace != "") |>
  filter(!is.na(titulo) & titulo != "") |>
  mutate(
    enlace            = sub("\\?(utm_|ref_|fbclid).*", "", enlace),
    fuente            = if_else(
      is.na(fuente) | fuente == "",
      sub("^https?://([^/]+).*$", "\\1", enlace),
      fuente
    ),
    fecha_chunk_desde = as.Date(fecha_chunk_desde),
    cuerpo            = if_else(is.na(cuerpo) | cuerpo == "", resumen, cuerpo)
  ) |>
  distinct(enlace, .keep_all = TRUE) |>
  distinct(titulo, .keep_all = TRUE) |>
  filter(
    fecha_chunk_desde >= fecha_inicio_muestra,
    fecha_chunk_desde <= fecha_fin_muestra
  ) |>
  arrange(localidad, fecha_chunk_desde)


# 6. Almacenamiento de microdatos y metadatos muestrales -----------------------

write_parquet(df_muestra_limpia, archivo_consolidado)
saveRDS(df_muestra_limpia, archivo_consol_rds)

tabla_cobertura <- df_muestra_limpia |>
  group_by(localidad) |>
  summarise(
    noticias_consolidadas = n(),
    fecha_min             = as.character(min(fecha_chunk_desde, na.rm = TRUE)),
    fecha_max             = as.character(max(fecha_chunk_desde, na.rm = TRUE)),
    meses_cubiertos       = list(sort(unique(format(fecha_chunk_desde, "%Y-%m")))),
    fuentes_principales   = list(head(names(sort(table(fuente), decreasing = TRUE)), 5)),
    .groups               = "drop"
  )

metadatos_auditoria <- list(
  proyecto                 = "Hurtos y Sentimiento Mediatico en Bogota (2022-2026)",
  fecha_actualizacion      = as.character(Sys.time()),
  total_filas_consolidadas = nrow(df_muestra_limpia),
  rango_generalizable      = list(
    inicio = as.character(min(df_muestra_limpia$fecha_chunk_desde, na.rm = TRUE)),
    fin    = as.character(max(df_muestra_limpia$fecha_chunk_desde, na.rm = TRUE))
  ),
  localidades              = split(tabla_cobertura, seq_len(nrow(tabla_cobertura)))
)

write_json(metadatos_auditoria, archivo_cobertura, pretty = TRUE, auto_unbox = TRUE)


# 7. Resumen descriptivo de la muestra procesada -------------------------------

conteo_anual <- df_muestra_limpia |>
  mutate(año = year(fecha_chunk_desde)) |>
  count(año, name = "articulos") |>
  as.data.frame()

conteo_localidades <- df_muestra_limpia |>
  count(localidad, sort = TRUE, name = "articulos") |>
  head(10) |>
  as.data.frame()

conteo_fuentes <- df_muestra_limpia |>
  count(fuente, sort = TRUE, name = "articulos") |>
  head(5) |>
  as.data.frame()

valores_faltantes <- data.frame(
  variable = c("titulo", "resumen", "enlace", "cuerpo"),
  nulos    = c(
    sum(is.na(df_muestra_limpia$titulo)),
    sum(is.na(df_muestra_limpia$resumen)),
    sum(is.na(df_muestra_limpia$enlace)),
    sum(is.na(df_muestra_limpia$cuerpo))
  )
)

print(conteo_anual, row.names = FALSE)
print(conteo_localidades, row.names = FALSE)
print(conteo_fuentes, row.names = FALSE)
print(valores_faltantes, row.names = FALSE)
