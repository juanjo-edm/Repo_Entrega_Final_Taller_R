# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediatico en Bogota (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R
# ROL: Ingesta, depuracion y consolidacion de prensa digital (Google News RSS)
# AUTORES: Juan Jose Echeverry, Miguelangel Palma, Sergio Lopez (Grupo 10)
# PROGRAMA: Maestria en Economia Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# METODOLOGIA Y FLUJO SECUENCIAL:
# Este script implementa un pipeline procedimental puro y lineal para la
# construccion del corpus periodistico sobre criminalidad y percepcion de
# seguridad en Bogota D.C. entre enero de 2022 y septiembre de 2026.
#
# El diseno sigue una arquitectura estrictamente secuencial (de arriba hacia abajo)
# y prescinde de funciones envolventes personalizadas. Esta decision metodologica
# permite:
#   1. Inspeccionar interactivamente en memoria cada paso del procesamiento.
#   2. Garantizar la trazabilidad y reproducibilidad econometrica de los datos.
#   3. Evaluar de manera transparente las transformaciones aplicadas a cada variable.
#
# ESTRUCTURA DEL PIPELINE:
#   Seccion 1: Configuracion del entorno, resolucion de colisiones y dependencias.
#   Seccion 2: Definicion del catalogo territorial y construccion de consultas booleanas.
#   Seccion 3: Recoleccion de notas de prensa recientes via feed Google News RSS.
#   Seccion 4: Consolidacion y union vertical de subtablas historicas y nuevos lotes.
#   Seccion 5: Normalizacion de campos, deduplicacion dual y delimitacion muestral.
#   Seccion 6: Almacenamiento optimizado de microdatos (Parquet, RDS) y metadatos JSON.
#   Seccion 7: Reporte descriptivo de frecuencias y control de valores faltantes.
# ==============================================================================


# ------------------------------------------------------------------------------
# 1. ENTORNO DE TRABAJO, RESOLUCION DE CONFLICTOS Y LIBRERIAS
# ------------------------------------------------------------------------------

# Desactivar notacion cientifica para preservar identificadores numericos y fechas
options(scipen = 999)

# Fijar semilla pseudoaleatoria para reproducibilidad en procesos muestrales
set.seed(20261014)

# Carga de paquetes del ecosistema R requeridos:
# - here: Construccion de rutas relativas independientes del sistema operativo.
# - conflicted: Manejo estricto de colisiones entre nombres de funciones de distintas librerias.
# - arrow: Lectura y escritura en formato columnar Apache Parquet (alta compresion y velocidad I/O).
# - readr: Lectura de archivos delimitados y soporte de parseo rapido.
# - dplyr: Gramatica fundamental para la transformacion, filtrado y manipulacion de datos.
# - tidyr: Herramientas para ordenamiento y estructuracion de datos en formato 'tidy'.
# - stringr: Funciones vectorizadas para el procesamiento y manipulacion de cadenas de texto.
# - stringi: Estandarizacion de caracteres, transliteracion y remocion de acentos ortograficos.
# - lubridate: Manipulacion y operaciones aritmeticas sobre calendarios y marcas temporales.
# - xml2: Lectura, extraccion y navegacion en documentos XML y feeds RSS de sindicacion.
# - rvest: Procesamiento y extraccion de contenido en etiquetas HTML web.
# - httr: Protocolo de peticiones cliente HTTP con control de encabezados y tiempos de espera.
# - jsonlite: Serializacion y parseo de metadatos en formato estructurado JSON.
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

# Resolucion explicita de colisiones mediante el paquete {conflicted}:
# Esto asegura que llamadas como filter(), lag() o select() provengan siempre
# del paquete adecuado sin necesidad de prefijar constantemente con el operador ::.
conflict_prefer("filter", "dplyr")
conflict_prefer("lag", "dplyr")
conflict_prefer("select", "dplyr")
conflict_prefer("duration", "lubridate")
conflict_prefer("guess_encoding", "readr")
conflict_prefer("timestamp", "utils")

# Definicion de rutas absolutas relativas a la raiz del repositorio
ruta_datos_raw      <- here("data", "raw")
ruta_noticias_raw   <- here("data", "raw", "noticias")
archivo_consolidado <- here("data", "raw", "noticias_google_news_consolidado.parquet")
archivo_consol_rds  <- here("data", "raw", "noticias_google_news_consolidado.rds")
archivo_cobertura   <- here("data", "raw", "noticias", "cobertura_historica.json")

# Creacion del directorio de almacenamiento primario si no existe previamente
if (!dir.exists(ruta_noticias_raw)) {
  dir.create(ruta_noticias_raw, recursive = TRUE)
}

# Parametros del horizonte temporal de investigacion:
# El periodo de analisis abarca desde el 1 de enero de 2022 hasta el 30 de septiembre de 2026.
fecha_inicio_muestra  <- as.Date("2022-01-01")
fecha_fin_muestra     <- as.Date("2026-09-30")

# Interruptor de ejecucion en vivo:
# - TRUE: Realiza peticiones web al feed de Google News para descargar notas recientes.
# - FALSE: Omite la descarga web y procede a consolidar, filtrar y auditar los datos locales existentes.
ejecutar_descarga_rss <- FALSE


# ------------------------------------------------------------------------------
# 2. CATALOGO DE LOCALIDADES Y ESPECIFICACION DE CONSULTAS BOOLEANAS
# ------------------------------------------------------------------------------

# Vector con las 19 localidades urbanas del Distrito Capital de Bogota.
# (Se excluye la localidad 20, Sumapaz, debido a su naturaleza netamente rural y a la
# ausencia de registros periodisticos continuos sobre criminalidad urbana en prensa digital).
localidades_bogota <- c(
  "Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
  "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá",
  "Suba", "Barrios Unidos", "Teusaquillo", "Los Mártires",
  "Antonio Nariño", "Puente Aranda", "La Candelaria", 
  "Rafael Uribe Uribe", "Ciudad Bolívar"
)

# Diccionario de terminos asociados a conductas delictivas de alto impacto ciudadano
terminos_delitos <- "(hurto OR robo OR atraco OR asalto OR inseguridad)"

# Construccion procedimental de la tabla de consultas:
# 1. termino_localidad: Encierra el nombre entre comillas dobles para forzar busqueda textual exacta.
# 2. filtro_exclusiones: Para la localidad de Santa Fe se excluyen explicitamente terminos futbolisticos
#    (-futbol, -liga, -campin, -dimayor, -cardenal) para neutralizar el sesgo que genera el club de futbol.
# 3. cadena_busqueda: Concatenacion limpia y normalizada de los terminos de delito, ciudad y territorio.
# 4. url_rss: URL parametrizada para el endpoint de Google News RSS con idioma espanol y region Colombia.
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


# ------------------------------------------------------------------------------
# 3. RECOLECCION SECUENCIAL VIA GOOGLE NEWS RSS (BUCLE DIRECTO)
# ------------------------------------------------------------------------------

# Este bloque se ejecuta unicamente cuando ejecutar_descarga_rss = TRUE.
# Realiza consultas secuenciales al feed XML oficial, extrayendo metadatos estructurados
# sin requerir navegadores automatizados ni generar riesgos de bloqueos por captcha.
if (isTRUE(ejecutar_descarga_rss)) {
  for (i in seq_len(nrow(df_consultas))) {
    loc_nombre <- df_consultas$localidad[i]
    url_actual <- df_consultas$url_rss[i]
    
    # Generacion de identificador slug sin caracteres especiales para el archivo particionado
    slug_loc <- tolower(stri_trans_general(loc_nombre, "Latin-ASCII"))
    slug_loc <- gsub("[^a-z0-9]", "_", slug_loc)
    archivo_chunk <- file.path(ruta_noticias_raw, paste0("chunk_rss_", slug_loc, ".parquet"))
    
    # Manejo de excepciones para asegurar que un fallo de red en una localidad no detenga el bucle
    tryCatch({
      # Lectura y parseo del documento XML de la respuesta RSS
      doc_xml    <- read_xml(url_actual)
      nodos_item <- xml_find_all(doc_xml, "//item")
      
      if (length(nodos_item) > 0) {
        # Extraccion de elementos nodales del XML
        titulos_raw <- xml_text(xml_find_first(nodos_item, "title"))
        enlaces_raw <- xml_text(xml_find_first(nodos_item, "link"))
        fechas_raw  <- xml_text(xml_find_first(nodos_item, "pubDate"))
        fuentes_raw <- xml_text(xml_find_first(nodos_item, "source"))
        desc_raw    <- xml_text(xml_find_first(nodos_item, "description"))
        
        # Limpieza de etiquetas HTML en los textos de resumen informativo
        resumenes_limpios <- character(length(desc_raw))
        for (k in seq_along(desc_raw)) {
          resumenes_limpios[k] <- tryCatch(
            read_html(desc_raw[k]) |> html_text(trim = TRUE),
            error = function(e) desc_raw[k]
          )
        }
        
        # Conversion de fechas estandar RFC 822 (GMT/RSS) a objetos Date de R
        fechas_parseadas <- as.Date(parse_date_time(
          fechas_raw,
          orders = c("dmy HMS", "ymd HMS", "a d b Y HMS z", "a d b Y")
        ))
        
        # Remocion de parametros de seguimiento web y analitica (UTM, ref, fbclid)
        enlaces_limpios <- sub("\\?(utm_|ref_|fbclid).*", "", enlaces_raw)
        
        # Estructuracion del lote de datos en formato tabular
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
        
        # Guardado incremental del lote particionado en formato Parquet
        write_parquet(df_chunk, archivo_chunk)
      }
    }, error = function(e) {
      warning(paste("Fallo en peticion para:", loc_nombre))
    })
    
    # Pausa de cortesía para no saturar las conexiones del servidor
    Sys.sleep(1.0)
  }
}


# ------------------------------------------------------------------------------
# 4. CONSOLIDACION DE REGISTROS HISTORICOS Y PARTICIONES RECIENTES
# ------------------------------------------------------------------------------

# 4.1 Carga de la serie consolidada preexistente en disco (si existe)
df_historico_previo <- tibble()
if (file.exists(archivo_consolidado)) {
  df_historico_previo <- read_parquet(archivo_consolidado)
}

# 4.2 Carga secuencial de todas las particiones Parquet generadas en data/raw/noticias/
archivos_particiones <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)

lista_particiones <- vector("list", length(archivos_particiones))
for (j in seq_along(archivos_particiones)) {
  lista_particiones[[j]] <- tryCatch(
    read_parquet(archivos_particiones[j]),
    error = function(e) tibble()
  )
}
df_particiones <- bind_rows(lista_particiones)

# 4.3 Fasion vertical de observaciones historicas y registros recientes
df_unificado_bruto <- bind_rows(df_historico_previo, df_particiones)


# ------------------------------------------------------------------------------
# 5. NORMALIZACION, DEDUPLICACION DUAL Y DELIMITACION TEMPORAL
# ------------------------------------------------------------------------------

# Procedimiento de depuracion econometrica y control de calidad:
# 1. Filtro de registros espurios con enlaces o titulares vacios.
# 2. Desinfeccion de enlaces web (limpieza de cadenas de consulta analiticas).
# 3. Imputacion de medio de comunicacion (fuente): si el campo esta vacio, se extrae el dominio web del enlace.
# 4. Deduplicacion en dos etapas:
#    a. Primer nivel: Por enlace web canonico unico (evita registros duplicados de una misma noticia).
#    b. Segundo nivel: Por titular identico (elimina notas republicadas bajo distintas URLs por agencias de noticias).
# 5. Delimitacion temporal estricta: Se acota la muestra al periodo entre fecha_inicio_muestra y fecha_fin_muestra.
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


# ------------------------------------------------------------------------------
# 6. ALMACENAMIENTO DE MICRODATOS Y METADATOS MUESTRALES
# ------------------------------------------------------------------------------

# 6.1 Exportacion de la base definitiva en formato Parquet (optimo para analisis columnar masivo)
write_parquet(df_muestra_limpia, archivo_consolidado)

# 6.2 Exportacion en formato nativo serializado de R (.rds) para compatibilidad plena
saveRDS(df_muestra_limpia, archivo_consol_rds)

# 6.3 Construccion de la matriz agregada de cobertura territorial para metadatos
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

# 6.4 Serializacion del registro de cobertura y trazabilidad en JSON
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


# ------------------------------------------------------------------------------
# 7. RESUMEN DESCRIPTIVO DE LA MUESTRA PROCESADA
# ------------------------------------------------------------------------------

# 7.1 Distribucion de observaciones por ano de publicacion
conteo_anual <- df_muestra_limpia |>
  mutate(año = year(fecha_chunk_desde)) |>
  count(año, name = "articulos") |>
  as.data.frame()

# 7.2 Distribucion de observaciones por localidad (primeras 10 posiciones)
conteo_localidades <- df_muestra_limpia |>
  count(localidad, sort = TRUE, name = "articulos") |>
  head(10) |>
  as.data.frame()

# 7.3 Principales medios de comunicacion en la muestra (primeras 5 posiciones)
conteo_fuentes <- df_muestra_limpia |>
  count(fuente, sort = TRUE, name = "articulos") |>
  head(5) |>
  as.data.frame()

# 7.4 Tabla de diagnostico de completitud y recuento de valores faltantes (NA)
valores_faltantes <- data.frame(
  variable = c("titulo", "resumen", "enlace", "cuerpo"),
  nulos    = c(
    sum(is.na(df_muestra_limpia$titulo)),
    sum(is.na(df_muestra_limpia$resumen)),
    sum(is.na(df_muestra_limpia$enlace)),
    sum(is.na(df_muestra_limpia$cuerpo))
  )
)

# Impresion academica estructurada de los cuadros estadisticos
print(conteo_anual, row.names = FALSE)
print(conteo_localidades, row.names = FALSE)
print(conteo_fuentes, row.names = FALSE)
print(valores_faltantes, row.names = FALSE)
