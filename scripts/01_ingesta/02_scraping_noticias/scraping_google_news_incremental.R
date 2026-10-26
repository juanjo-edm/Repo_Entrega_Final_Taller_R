# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news_incremental.R
# ROL: Ampliación focalizada del corpus en las celdas localidad-mes con menos
#      cobertura, por familias de Delitos de Alto Impacto (DAI) de la SDSCJ.
# AUTOR: Gabriel Arturo Echeverry Castaño (Sub-equipo Datos y Modelado, Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# PROBLEMA QUE RESUELVE:
# La consulta actual (una por localidad, sin ventana de fechas) devuelve solo
# las ~100 notas más recientes que Google News tenga indexadas. Por eso la base
# crece con el tiempo (2022: ~300 notas DAI; 2026: ~965 en nueve meses) y
# quedan huecos como oct-dic 2025. Este script:
#   1. Identifica las celdas localidad x mes con menos notas DAI.
#   2. Lanza consultas por familia de delito con ventana mensual
#      (operadores after:/before:), que sí recuperan notas antiguas.
#   3. Registra cada consulta en una bitácora para no repetirla nunca.
#   4. Guarda cada corrida como un lote independiente (no toca el consolidado).
#
# CÓMO INTEGRAR EL LOTE (sección 4 de scraping_google_news.R):
#   lotes <- list.files(here("data","raw","noticias","lotes_incrementales"),
#                       pattern = "\\.rds$", full.names = TRUE)
#   df_nuevas_rss <- bind_rows(df_nuevas_rss, lapply(lotes, readRDS))
# Luego se corre el pipeline: scraping_google_news.R -> 02_limpieza_texto_noticias.R
#   -> 03_analisis_sentometrics.R -> 02b_depuracion_noticias_dai.R
#
# NOTA: las notas nuevas traen el fragmento del RSS como cuerpo (como las de
# 2026). Para que el sentimiento sea comparable entre años, conviene que el
# sub-equipo NLP calcule también el índice sobre `titulo + resumen` para todo
# el corpus.
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(here)       # Rutas relativas
library(conflicted) # Colisiones de funciones
library(dplyr)      # Manipulación
library(tidyr)      # complete() / expand_grid()
library(stringr)    # Texto
library(stringi)    # Normalización de tildes
library(lubridate)  # Fechas
library(xml2)       # Lectura del feed RSS
library(rvest)      # Limpieza del HTML del resumen
library(readr)      # Bitácora .csv

## 1.3 Resolución explícita de conflictos ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Rutas relativas ----
ruta_noticias_raw  <- here::here("data", "raw", "noticias")
ruta_lotes         <- file.path(ruta_noticias_raw, "lotes_incrementales")
archivo_bitacora   <- file.path(ruta_noticias_raw, "bitacora_consultas_incrementales.csv")
archivo_base_dai   <- here::here("data", "processed", "noticias", "noticias_dai.rds")
dir.create(ruta_lotes, recursive = TRUE, showWarnings = FALSE)

## 1.5 Parámetros de la corrida ----
fecha_inicio_muestra   <- as.Date("2022-01-01")
fecha_fin_muestra      <- as.Date("2026-09-30") # Alineado con el corte de SDSCJ
umbral_notas_celda     <- 4L    # Celdas localidad-mes por debajo se priorizan
max_consultas_corrida  <- 250L  # Tope por corrida (~15 min con pausas)
pausa_min_seg          <- 2.5   # Pausa aleatoria entre peticiones
pausa_max_seg          <- 5.0
ejecutar_descarga      <- FALSE # Cambiar a TRUE para descargar

# Reparto opcional del trabajo entre integrantes (NULL = todas)
localidades_asignadas  <- NULL  # p.ej. c("Fontibón", "Usme", "Tunjuelito")

# 2. Catálogo Territorial y Familias de Consulta ----

## 2.1 Localidades y exclusiones por homonimia (mismas del scraper original) ----
catalogo_localidades <- tibble(
  localidad = c("Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
                "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá", "Suba",
                "Barrios Unidos", "Teusaquillo", "Los Mártires", "Antonio Nariño",
                "Puente Aranda", "La Candelaria", "Rafael Uribe Uribe", "Ciudad Bolívar")
) |>
  mutate(
    loc_slug = tolower(stri_trans_general(localidad, "Latin-ASCII")),
    exclusiones = case_when(
      loc_slug == "santa fe"           ~ "-futbol -liga -campin -dimayor -partido -estadio -gol",
      loc_slug == "san cristobal"      ~ "-venezuela -tachira -mexico -chiapas",
      loc_slug == "la candelaria"      ~ "-medellin -valle -antioquia -atlantico",
      loc_slug == "ciudad bolivar"     ~ "-venezuela -antioquia -orinoco",
      loc_slug == "antonio narino"     ~ "-universidad -uan -pregrado -matricula -facultad",
      loc_slug == "rafael uribe uribe" ~ "-cali",
      loc_slug == "bosa"               ~ "-italia",
      TRUE                             ~ ""
    )
  )

## 2.2 Familias de consulta alineadas con los 11 DAI ----
# Agrupar en cinco familias mantiene las cadenas cortas (Google News trunca
# consultas largas) y multiplica la recuperación frente a una sola consulta.
familias_dai <- tibble(
  familia = c("hurto_personas", "hurto_inmuebles", "hurto_vehiculos",
              "vida_integridad", "extorsion_sexual_vif"),
  terminos = c(
    "(hurto OR robo OR atraco OR raponazo OR cosquilleo OR fleteo OR celular OR bicicleta)",
    "(hurto OR robo OR asalto) (residencia OR apartamento OR vivienda OR comercio OR tienda OR local OR banco)",
    "(hurto OR robo) (carro OR vehículo OR camioneta OR moto OR motocicleta OR autopartes)",
    "(homicidio OR asesinato OR sicariato OR feminicidio OR apuñalado OR riña OR \"lesiones personales\")",
    "(extorsión OR \"abuso sexual\" OR \"delito sexual\" OR \"violencia intrafamiliar\")"
  )
)

# 3. Selección de Celdas Prioritarias ----

## 3.1 Conteo actual de notas DAI por localidad-mes ----
meses_muestra <- seq(fecha_inicio_muestra, floor_date(fecha_fin_muestra, "month"), by = "month")

conteo_actual <- readRDS(archivo_base_dai) |>
  mutate(mes_inicio = floor_date(as.Date(fecha), "month")) |>
  count(localidad, mes_inicio, name = "notas_dai")

celdas <- expand_grid(localidad = catalogo_localidades$localidad, mes_inicio = meses_muestra) |>
  left_join(conteo_actual, by = c("localidad", "mes_inicio")) |>
  mutate(notas_dai = coalesce(notas_dai, 0L)) |>
  filter(notas_dai < umbral_notas_celda)

if (!is.null(localidades_asignadas)) {
  celdas <- celdas |> filter(localidad %in% localidades_asignadas)
}

## 3.2 Plan de consultas: celdas deficitarias x familias, sin repetir bitácora ----
bitacora <- if (file.exists(archivo_bitacora)) {
  read_csv(archivo_bitacora, show_col_types = FALSE,
           col_types = cols(mes_inicio = col_date(), .default = col_guess()))
} else {
  tibble(localidad = character(), familia = character(), mes_inicio = as.Date(character()),
         n_items = integer(), estado = character(), fecha_consulta = as.POSIXct(character()))
}

plan_consultas <- celdas |>
  cross_join(familias_dai) |>
  anti_join(bitacora |> filter(estado == "ok"), by = c("localidad", "familia", "mes_inicio")) |>
  left_join(catalogo_localidades, by = "localidad") |>
  mutate(
    mes_fin = mes_inicio %m+% months(1),
    cadena  = str_squish(paste(
      terminos, "Bogotá", paste0('"', localidad, '"'), exclusiones,
      paste0("after:", format(mes_inicio - days(1), "%Y-%m-%d")),
      paste0("before:", format(mes_fin, "%Y-%m-%d"))
    )),
    url_rss = paste0("https://news.google.com/rss/search?q=",
                     URLencode(cadena, reserved = TRUE),
                     "&hl=es-419&gl=CO&ceid=CO:es-419")
  ) |>
  # Primero las celdas más vacías y los meses más antiguos
  arrange(notas_dai, mes_inicio, localidad, familia) |>
  slice_head(n = max_consultas_corrida)

message(">>> Celdas deficitarias: ", nrow(celdas),
        " | Consultas pendientes en esta corrida: ", nrow(plan_consultas))

# 4. Descarga y Parseo del Feed ----

## 4.1 Parseo de un documento RSS a tibble con el esquema del scraper original ----
parsear_rss <- function(doc_xml, localidad, cadena) {
  items <- xml_find_all(doc_xml, "//item")
  if (length(items) == 0) return(NULL)

  desc_html <- xml_text(xml_find_first(items, "description"))
  resumen   <- vapply(desc_html, function(h) {
    tryCatch(html_text(read_html(paste0("<div>", h, "</div>")), trim = TRUE),
             error = function(e) h)
  }, character(1), USE.NAMES = FALSE)

  fecha_pub <- as.Date(parse_date_time(xml_text(xml_find_first(items, "pubDate")),
                                       orders = c("a d b Y HMS z", "d b Y HMS", "ymd HMS")))
  tibble(
    localidad         = localidad,
    consulta          = cadena,
    titulo            = xml_text(xml_find_first(items, "title")),
    resumen           = resumen,
    fuente            = xml_text(xml_find_first(items, "source")),
    fecha_texto       = xml_text(xml_find_first(items, "pubDate")),
    fecha_iso         = as.character(fecha_pub),
    enlace            = sub("\\?(utm_|ref_|fbclid).*", "", xml_text(xml_find_first(items, "link"))),
    fecha_chunk_desde = floor_date(fecha_pub, "month"),
    fecha_chunk_hasta = ceiling_date(fecha_pub, "month") - days(1),
    pagina            = 1L,
    cuerpo            = resumen,
    origen_lote       = "incremental_dai"
  ) |>
    filter(!is.na(titulo), titulo != "", !is.na(enlace), enlace != "") |>
    # Google News pone " - Medio" al final del titular; se conserva igual que
    # en la base histórica para que la deduplicación por titular funcione.
    distinct(enlace, .keep_all = TRUE)
}

## 4.2 Bucle de descarga con bitácora ----
if (isTRUE(ejecutar_descarga) && nrow(plan_consultas) > 0) {

  resultados <- vector("list", nrow(plan_consultas))
  registros  <- vector("list", nrow(plan_consultas))

  for (i in seq_len(nrow(plan_consultas))) {
    fila <- plan_consultas[i, ]
    estado <- "ok"
    df_i <- tryCatch(
      parsear_rss(read_xml(fila$url_rss), fila$localidad, fila$cadena),
      error = function(e) { estado <<- paste("error:", conditionMessage(e)); NULL }
    )
    # Solo se conservan notas dentro de la ventana pedida
    if (!is.null(df_i)) {
      df_i <- df_i |> filter(as.Date(fecha_iso) >= fila$mes_inicio,
                             as.Date(fecha_iso) <  fila$mes_fin)
    }
    resultados[[i]] <- df_i
    registros[[i]]  <- tibble(localidad = fila$localidad, familia = fila$familia,
                              mes_inicio = fila$mes_inicio,
                              n_items = if (is.null(df_i)) 0L else nrow(df_i),
                              estado = estado, fecha_consulta = Sys.time())
    if (i %% 25 == 0) message("   ", i, "/", nrow(plan_consultas), " consultas")
    Sys.sleep(runif(1, pausa_min_seg, pausa_max_seg))
  }

  # 5. Deduplicación contra la Base Existente y Guardado ----
  base_existente <- readRDS(archivo_base_dai)
  normalizar_titulo <- function(x) str_squish(tolower(stri_trans_general(x, "Latin-ASCII")))

  lote <- bind_rows(resultados) |>
    distinct(enlace, .keep_all = TRUE) |>
    mutate(titulo_norm = normalizar_titulo(titulo)) |>
    distinct(titulo_norm, .keep_all = TRUE) |>
    filter(!enlace %in% base_existente$enlace,
           !titulo_norm %in% normalizar_titulo(base_existente$titulo)) |>
    select(-titulo_norm)

  sello <- format(Sys.time(), "%Y%m%d_%H%M%S")
  saveRDS(lote, file.path(ruta_lotes, paste0("lote_", sello, ".rds")))
  if (requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_parquet(lote, file.path(ruta_lotes, paste0("lote_", sello, ".parquet")))
  }

  write_csv(bind_rows(bitacora, bind_rows(registros)), archivo_bitacora)

  message("\n=== Corrida terminada ===")
  message("Notas nuevas (no duplicadas): ", nrow(lote))
  print(count(bind_rows(registros), estado))
  print(lote |> count(año = year(as.Date(fecha_iso))))
} else {
  message("ejecutar_descarga = FALSE: solo se generó el plan de consultas.")
  print(plan_consultas |> count(año = year(mes_inicio), name = "consultas_planeadas"))
}
