# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/01_ingesta/03_noticias/scraping_google_news.R
# ROL: Ingesta y Consolidación de Prensa Digital (Flujo Tidyverse)
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE: data/raw/noticias/noticias_google_news_consolidado.parquet y .rds


# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y dependencias ----
options(scipen = 999)
set.seed(20261014)

library(here)
library(conflicted)
library(arrow)
library(tibble)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(stringi)
library(lubridate)
library(xml2)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("duration", "lubridate", quiet = TRUE)

## 1.2 Rutas relativas de almacenamiento ----
ruta_noticias_raw   <- here("data", "raw", "noticias")
archivo_consolidado <- file.path(ruta_noticias_raw, "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- file.path(ruta_noticias_raw, "noticias_google_news_consolidado.rds")

if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE, showWarnings = FALSE)
}

## 1.3 Parámetros de ejecución ----
if (!exists("modo_scraping")) {
  modo_scraping <- "consolidar"
}

fecha_inicio_muestra  <- as.Date("2022-01-01")
fecha_fin_muestra     <- as.Date("2026-09-30")
umbral_notas_celda    <- 4L
max_consultas_corrida <- 250L
pausa_min_seg         <- 1.0
pausa_max_seg         <- 2.5

# 2. Catálogo Territorial, Homonimias y Familias DAI ----

## 2.1 Mapeo de localidades y filtros de exclusión ----
catalogo_localidades <- tibble(
  localidad = c(
    "Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
    "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá",
    "Suba", "Barrios Unidos", "Teusaquillo", "Los Mártires",
    "Antonio Nariño", "Puente Aranda", "La Candelaria", 
    "Rafael Uribe Uribe", "Ciudad Bolívar"
  )
) |>
  mutate(
    loc_slug = tolower(stri_trans_general(localidad, "Latin-ASCII")),
    exclusiones = case_when(
      loc_slug == "santa fe"           ~ "-futbol -liga -campin -dimayor -cardenal -partido -estadio -gol -independiente -antioquia -ralito",
      loc_slug == "san cristobal"      ~ "-venezuela -tachira -mexico -chiapas -bolivar",
      loc_slug == "la candelaria"      ~ "-medellin -valle -antioquia -atlantico",
      loc_slug == "ciudad bolivar"     ~ "-venezuela -antioquia -orinoco",
      loc_slug == "antonio narino"     ~ "-universidad -uan -pregrado -matricula -facultad",
      loc_slug == "rafael uribe uribe" ~ "-cali",
      loc_slug == "bosa"               ~ "-italia -cerdeña",
      TRUE                             ~ ""
    )
  )

## 2.2 Familias de búsqueda booleana alineadas con los 11 DAI ----
# Taxonomía oficial de 11 Delitos de Alto Impacto (DAI) de la SDSCJ / SIEDCO:
# https://datosabiertos.bogota.gov.co/dataset/delito-de-alto-impacto-bogota-d-c
familias_dai <- tibble(
  familia = c(
    "hurto_personas",
    "hurto_inmuebles",
    "hurto_vehiculos",
    "vida_integridad",
    "extorsion_sexual_vif"
  ),
  terminos = c(
    "(hurto OR robo OR atraco OR raponazo OR cosquilleo OR fleteo OR celular OR bicicleta)",
    "(hurto OR robo OR asalto) (residencia OR apartamento OR vivienda OR comercio OR tienda OR local OR banco)",
    "(hurto OR robo) (carro OR vehiculo OR camioneta OR moto OR motocicleta OR autopartes)",
    "(homicidio OR asesinato OR sicariato OR feminicidio OR apunalado OR rina OR \"lesiones personales\")",
    "(extorsion OR \"abuso sexual\" OR \"delito sexual\" OR \"violencia intrafamiliar\")"
  )
)

## 2.3 Función de extracción y parseo XML de Google News RSS ----
parsear_rss <- function(url_rss, localidad, mes_inicio, mes_fin) {
  Sys.sleep(runif(1, pausa_min_seg, pausa_max_seg))
  
  doc_xml <- tryCatch(read_xml(url_rss), error = function(e) NULL)
  if (is.null(doc_xml)) return(tibble())
  
  items <- xml_find_all(doc_xml, "//item")
  if (length(items) == 0) return(tibble())
  
  tibble(
    localidad   = localidad,
    titulo      = xml_text(xml_find_first(items, "title")),
    desc_raw    = xml_text(xml_find_first(items, "description")),
    fuente      = xml_text(xml_find_first(items, "source")),
    fecha_texto = xml_text(xml_find_first(items, "pubDate")),
    enlace_raw  = xml_text(xml_find_first(items, "link"))
  ) |>
    mutate(
      resumen = str_squish(gsub("<[^>]+>", " ", desc_raw)),
      cuerpo  = resumen,
      fecha   = as.Date(parse_date_time(
        fecha_texto,
        orders = c("a d b Y HMS z", "d b Y HMS", "dmy HMS", "ymd HMS")
      )),
      enlace  = sub("\\?(utm_|ref_|fbclid).*", "", enlace_raw)
    ) |>
    select(-desc_raw, -enlace_raw, -fecha_texto) |>
    filter(
      !is.na(titulo), titulo != "",
      !is.na(enlace), enlace != "",
      fecha >= mes_inicio, fecha < mes_fin
    ) |>
    distinct(enlace, .keep_all = TRUE)
}

# 3. Carga y Scraping RSS en Google News ----

## 3.1 Carga de la base histórica existente ----
df_base <- if (file.exists(archivo_consolidado)) {
  read_parquet(archivo_consolidado)
} else if (file.exists(archivo_consol_rds)) {
  readRDS(archivo_consol_rds)
} else {
  tibble()
}

## 3.2 Modo Incremental: descarga de meses con baja cobertura ----
if (modo_scraping == "incremental" || nrow(df_base) == 0L) {
  message(">>> Modo incremental activo: buscando noticias faltantes en Google News RSS...")
  
  meses_muestra <- seq.Date(fecha_inicio_muestra, fecha_fin_muestra, by = "month")
  
  conteo_actual <- if (nrow(df_base) > 0L) {
    df_base |>
      mutate(mes_inicio = floor_date(as.Date(fecha), "month")) |>
      count(localidad, mes_inicio, name = "n")
  } else {
    tibble(localidad = character(), mes_inicio = as.Date(character()), n = integer())
  }
  
  df_nuevas_rss <- expand_grid(
    localidad  = catalogo_localidades$localidad,
    mes_inicio = meses_muestra
  ) |>
    left_join(conteo_actual, by = c("localidad", "mes_inicio")) |>
    mutate(n = coalesce(n, 0L)) |>
    filter(n < umbral_notas_celda) |>
    cross_join(familias_dai) |>
    left_join(catalogo_localidades, by = "localidad") |>
    mutate(
      mes_fin = mes_inicio %m+% months(1),
      cadena  = str_squish(paste(
        terminos, "Bogota", paste0('"', localidad, '"'), exclusiones, "-horoscopo -tarot",
        paste0("after:", format(mes_inicio - days(1), "%Y-%m-%d")),
        paste0("before:", format(mes_fin, "%Y-%m-%d"))
      )),
      url_rss = paste0(
        "https://news.google.com/rss/search?q=",
        URLencode(cadena, reserved = TRUE),
        "&hl=es-419&gl=CO&ceid=CO:es-419"
      )
    ) |>
    arrange(n, mes_inicio, localidad, familia) |>
    slice_head(n = max_consultas_corrida) |>
    mutate(
      articulos = pmap(list(url_rss, localidad, mes_inicio, mes_fin), parsear_rss)
    ) |>
    select(articulos) |>
    unnest(cols = articulos)
  
  df_base <- bind_rows(df_base, df_nuevas_rss)
  message("✔ Descarga RSS finalizada: ", nrow(df_nuevas_rss), " artículos recolectados.")
} else {
  message(">>> Modo consolidar: sincronizando y auditando base existente...")
}

# 4. Flujo Tidyverse: Limpieza y Deduplicación Dual ----

## 4.1 Normalización temporal y deduplicación dual ----

df_limpio <- df_base |>
  mutate(
    fecha  = as.Date(fecha),
    enlace = sub("\\?(utm_|ref_|fbclid).*", "", enlace),
    titulo = str_squish(titulo)
  ) |>
  filter(
    !is.na(fecha),
    between(fecha, fecha_inicio_muestra, fecha_fin_muestra),
    !is.na(titulo) & titulo != "",
    !is.na(enlace) & enlace != ""
  ) |>
  # 1. Deduplicación por enlace canónico
  distinct(enlace, .keep_all = TRUE) |>
  # 2. Deduplicación por titular exacto normalizado
  distinct(tolower(stri_trans_general(titulo, "Latin-ASCII")), .keep_all = TRUE)

# 5. Enriquecimiento Analítico Vectorizado en Mutate ----

## 5.1 Clasificación de medios, delitos DAI y confianza geográfica ----
df_enriquecido <- df_limpio |>
  mutate(
    año        = as.integer(year(fecha)),
    mes        = as.integer(month(fecha)),
    año_mes    = format(fecha, "%Y-%m"),
    trimestre  = paste0(año, "-Q", quarter(fecha)),
    semana_año = as.integer(isoweek(fecha)),
    fuente     = coalesce(fuente, "Prensa Digital"),
    cuerpo     = coalesce(cuerpo, resumen),
    
    # Textos de evaluación vectorizados
    texto_medios = tolower(paste(fuente, enlace)),
    texto_nlp    = tolower(stri_trans_general(paste(titulo, cuerpo), "Latin-ASCII")),
    
    # Tipología de medio de comunicación
    tipo_medio = case_when(
      str_detect(texto_medios, "alcaldia|policia|fiscalia|scj|concejo|seguridad|bogota\\.gov") ~ "Institucional",
      str_detect(texto_medios, "eltiempo|espectador|semana|portafolio|elpais|nuevosiglo|larepublica") ~ "Prensa Tradicional",
      str_detect(texto_medios, "citytv|noticias caracol|noticias rcn|blu radio|w radio|la fm|canal capital|red\\+ noticias") ~ "Television y Radio",
      str_detect(texto_medios, "infobae|pulzo|las2orillas|kienyke|minuto30|valora analitik") ~ "Nativo Digital",
      str_detect(texto_medios, "suba alternativa|barrios de bogota|periodico|adn") ~ "Prensa Local y Comunitaria",
      TRUE ~ "Prensa Digital General"
    ),
    
    # Homologación a los Delitos de Alto Impacto (SDSCJ / SIEDCO)
    delito_alto_impacto = case_when(
      str_detect(texto_nlp, "homicid|asesin|sicariat|muert|homicidio") ~ "Homicidio",
      str_detect(texto_nlp, "sexual|abuso sexual|violacion|violencia intrafamiliar") ~ "Delitos sexuales y violencia intrafamiliar",
      str_detect(texto_nlp, "extorsion|vacuna|boleteo|amenaza") ~ "Extorsion",
      str_detect(texto_nlp, "celular|telefono movil") ~ "Hurto de celulares",
      str_detect(texto_nlp, "bicicleta|biciusuario") ~ "Hurto de bicicletas",
      str_detect(texto_nlp, "moto|motocicleta") ~ "Hurto de motocicletas",
      str_detect(texto_nlp, "automotor|vehiculo|carro|camioneta|autoparte") ~ "Hurto de automotores y autopartes",
      str_detect(texto_nlp, "comercio|tienda|local|supermercado|almacen|bodega") ~ "Hurto a comercio",
      str_detect(texto_nlp, "residencia|casa|apartamento|vivienda") ~ "Hurto a residencias",
      str_detect(texto_nlp, "atraco|asalto|fleteo|hurto a persona") ~ "Hurto a personas",
      str_detect(texto_nlp, "lesion|herido|apunalado|golpiza|rina") ~ "Lesiones personales",
      str_detect(texto_nlp, "droga|estupefaciente|microtrafico|olla") ~ "Trafico local de estupefacientes",
      str_detect(texto_nlp, "captura|capturado|operativo|desarticulad|policia") ~ "Operatividad y capturas policiales",
      str_detect(texto_nlp, "seguridad|patrullaje|camaras|alcalde|prevencion") ~ "Politica de seguridad y prevencion",
      TRUE ~ "Hurto / Delincuencia comun no diferenciada"
    ),
    tipo_delito_dominante = delito_alto_impacto,
    
    # Confianza geográfica según presencia de hitos barriales de la localidad
    confianza_geografica = if_else(
      (localidad == "Usaquén"           & str_detect(texto_nlp, "cedritos|santa barbara|torca|unicentro")) |
      (localidad == "Chapinero"         & str_detect(texto_nlp, "chico|rosales|el retiro|marly|lago")) |
      (localidad == "Santa Fe"          & str_detect(texto_nlp, "la macarena|las aguas|las nieves|san victorino|la perseverancia")) |
      (localidad == "San Cristóbal"     & str_detect(texto_nlp, "20 de julio|la victoria|libertadores|quindio")) |
      (localidad == "Usme"              & str_detect(texto_nlp, "yomasa|alfonso lopez|danubio|monteblanco")) |
      (localidad == "Tunjuelito"        & str_detect(texto_nlp, "venecia|san carlos|tunal|el tunal|san benito")) |
      (localidad == "Bosa"              & str_detect(texto_nlp, "brasil|carbonell|porvenir|san bernardino|la libertad")) |
      (localidad == "Kennedy"           & str_detect(texto_nlp, "patio bonito|castilla|tintal|el tintal|corabastos|mandalay|timiza")) |
      (localidad == "Fontibón"          & str_detect(texto_nlp, "modelia|salitre|capellania|zona franca|san pablo")) |
      (localidad == "Engativá"          & str_detect(texto_nlp, "minuto de dios|boyaca real|alamos|quirigua|garces navas")) |
      (localidad == "Suba"              & str_detect(texto_nlp, "rincon|niza|colina campestre|tibabuyes|prado veraniego")) |
      (localidad == "Barrios Unidos"    & str_detect(texto_nlp, "7 de agosto|polo club|12 de octubre|la castellana")) |
      (localidad == "Teusaquillo"       & str_detect(texto_nlp, "palermo|galerias|parkway|ciudad salitre|la soledad")) |
      (localidad == "Los Mártires"      & str_detect(texto_nlp, "santa isabel|ricaurte|la sabana|voto nacional")) |
      (localidad == "Antonio Nariño"    & str_detect(texto_nlp, "restrepo|santander|policarpa|ciudad berna")) |
      (localidad == "Puente Aranda"     & str_detect(texto_nlp, "ciudad montes|salazar gomez|gorgonzola")) |
      (localidad == "La Candelaria"     & str_detect(texto_nlp, "centro historico|plaza de bolivar|belen")) |
      (localidad == "Rafael Uribe Uribe"& str_detect(texto_nlp, "olaya|quiroga|san jose|diana turbay|marruecos")) |
      (localidad == "Ciudad Bolívar"    & str_detect(texto_nlp, "meissen|sierra morena|arborizadora|lucero|san francisco|jerusalen")),
      "Alta", "Media"
    )
  ) |>
  select(
    fecha, año, mes, año_mes, trimestre, semana_año,
    localidad, confianza_geografica, fuente, tipo_medio,
    delito_alto_impacto, tipo_delito_dominante,
    titulo, resumen, cuerpo, enlace
  )

# 6. Almacenamiento Centralizado e Idempotente ----

## 6.1 Exportación a Parquet y RDS nativo ----
write_parquet(df_enriquecido, archivo_consolidado)
saveRDS(df_enriquecido, archivo_consol_rds)

## 6.2 Control de calidad de la base procesada ----
stopifnot(nrow(df_enriquecido) > 0)
stopifnot(all(!is.na(df_enriquecido$fecha)))
stopifnot(all(!is.na(df_enriquecido$titulo)))

message("✔ Ingesta de noticias completada: ", nrow(df_enriquecido), 
        " artículos consolidados (2022-2026), 0 valores nulos.")
