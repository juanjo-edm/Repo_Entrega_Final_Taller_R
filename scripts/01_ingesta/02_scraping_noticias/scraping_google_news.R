# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediatico en Bogota (2022-2026)
# ARCHIVO: scripts/01_ingesta/02_scraping_noticias/scraping_google_news.R
# ROL: Ingesta, depuracion, enriquecimiento y consolidacion de prensa digital
# AUTORES: Juan Jose Echeverry, Miguelangel Palma, Sergio Lopez (Grupo 10)
# PROGRAMA: Maestria en Economia Aplicada (MECA) — Universidad de los Andes
# ==============================================================================
#
# METODOLOGIA Y FLUJO SECUENCIAL:
# Este script implementa un pipeline procedimental puro y lineal para la
# construccion y enriquecimiento analitico del corpus periodistico sobre
# criminalidad y percepcion de seguridad en Bogota D.C. (2022 - 2026).
#
# ESTRUCTURA PROCEDIMENTAL DEL PIPELINE:
#   Seccion 1: Configuracion del entorno, resolucion de colisiones y librerias.
#   Seccion 2: Definicion del catalogo territorial y consultas booleanas.
#   Seccion 3: Recoleccion de notas de prensa recientes via feed Google News RSS.
#   Seccion 4: Consolidacion y union vertical de subtablas historicas y lotes.
#   Seccion 5: Normalizacion de campos, deduplicacion dual y delimitacion muestral.
#   Seccion 6: Enriquecimiento analitico con diccionarios tematicos ampliados:
#              - Tipificacion de medios de comunicacion (sesgos editoriales).
#              - Validacion territorial y determinacion de confianza geografica.
#              - Clasificacion exhaustiva de modalidades delictivas y hechos de seguridad.
#              - Estructura temporal para modelacion en panel (ano, mes, trimestre, semana).
#   Seccion 7: Almacenamiento optimizado de microdatos (Parquet, RDS) y metadatos JSON.
#   Seccion 8: Resumen descriptivo de la muestra y diagnostico de integridad.
# ==============================================================================


# ------------------------------------------------------------------------------
# 1. ENTORNO DE TRABAJO, RESOLUCION DE CONFLICTOS Y LIBRERIAS
# ------------------------------------------------------------------------------

# Desactivar notacion cientifica para preservar codigos numericos e identificadores
options(scipen = 999)

# Fijar semilla pseudoaleatoria para reproducibilidad global
set.seed(20261014)

# Carga de paquetes del ecosistema R requeridos
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

# Resolucion explicita de colisiones entre funciones mediante {conflicted}
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

# Parametros del horizonte temporal de investigacion (2022-01-01 a 2026-09-30)
fecha_inicio_muestra  <- as.Date("2022-01-01")
fecha_fin_muestra     <- as.Date("2026-09-30")

# Interruptor de ejecucion de raspado web:
# FALSE: Utiliza y consolida la informacion local ya descargada.
# TRUE: Ejecuta consultas web adicionales a Google News RSS.
ejecutar_descarga_rss <- FALSE


# ------------------------------------------------------------------------------
# 2. CATALOGO DE LOCALIDADES Y ESPECIFICACION DE CONSULTAS BOOLEANAS
# ------------------------------------------------------------------------------

# Vector con las 19 localidades urbanas del Distrito Capital de Bogota
localidades_bogota <- c(
  "Usaquén", "Chapinero", "Santa Fe", "San Cristóbal", "Usme",
  "Tunjuelito", "Bosa", "Kennedy", "Fontibón", "Engativá",
  "Suba", "Barrios Unidos", "Teusaquillo", "Los Mártires",
  "Antonio Nariño", "Puente Aranda", "La Candelaria", 
  "Rafael Uribe Uribe", "Ciudad Bolívar"
)

# Diccionario tematico de delitos asociados a la seguridad ciudadana
terminos_delitos <- "(hurto OR robo OR atraco OR asalto OR inseguridad)"

# Construccion procedimental de la tabla de consultas:
# - Se entrecomilla el territorio para forzar coincidencia textual exacta.
# - Para Santa Fe se excluyen terminos futbolisticos para neutralizar el sesgo del club homonimo.
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


# ------------------------------------------------------------------------------
# 4. CONSOLIDACION DE REGISTROS HISTORICOS Y PARTICIONES RECIENTES
# ------------------------------------------------------------------------------

# Carga de la serie consolidada preexistente
df_historico_previo <- tibble()
if (file.exists(archivo_consolidado)) {
  df_historico_previo <- read_parquet(archivo_consolidado)
}

# Carga de todos los lotes Parquet particionados
archivos_particiones <- list.files(ruta_noticias_raw, pattern = "^chunk_.*\\.parquet$", full.names = TRUE)

lista_particiones <- vector("list", length(archivos_particiones))
for (j in seq_along(archivos_particiones)) {
  lista_particiones[[j]] <- tryCatch(
    read_parquet(archivos_particiones[j]),
    error = function(e) tibble()
  )
}
df_particiones <- bind_rows(lista_particiones)

# Fusion vertical
df_unificado_bruto <- bind_rows(df_historico_previo, df_particiones)


# ------------------------------------------------------------------------------
# 5. NORMALIZACION, DEDUPLICACION DUAL Y DELIMITACION TEMPORAL
# ------------------------------------------------------------------------------

df_muestra_base <- df_unificado_bruto |>
  # Estandarizacion de nombres de localidad (ej. Candelaria -> La Candelaria)
  mutate(
    localidad = if_else(localidad == "Candelaria", "La Candelaria", localidad)
  ) |>
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
  # Criterio de deduplicacion dual (URL canonica y titular textual exacto)
  distinct(enlace, .keep_all = TRUE) |>
  distinct(titulo, .keep_all = TRUE) |>
  filter(
    fecha_chunk_desde >= fecha_inicio_muestra,
    fecha_chunk_desde <= fecha_fin_muestra
  )


# ------------------------------------------------------------------------------
# 6. ENRIQUECIMIENTO ANALITICO CON DICCIONARIOS TEMATICOS Y PANEL
# ------------------------------------------------------------------------------

# 6.1 MEJORA 1: Tipificacion y categorizacion de medios de comunicacion
# Permite controlar econométricamente por sesgos editoriales (institucional vs. alarma ciudadana)
fuente_lower <- tolower(df_muestra_base$fuente)

df_muestra_enriquecida <- df_muestra_base |>
  mutate(
    tipo_medio = case_when(
      str_detect(fuente_lower, "bogota\\.gov|alcaldia|concejodebogota|policia|fiscalia|personeria|gobierno") ~ "Institucional",
      str_detect(fuente_lower, "eltiempo|el tiempo|elespectador|el espectador|semana|portafolio|el pais|el nuevo siglo|la republica") ~ "Prensa Tradicional",
      str_detect(fuente_lower, "citytv|city tv|caracol|rcn|blu radio|w radio|la fm|canal capital|red\\+ noticias") ~ "Television y Radio",
      str_detect(fuente_lower, "infobae|pulzo|las2orillas|kienyke|minuto30|valora analitik") ~ "Nativo Digital",
      str_detect(fuente_lower, "suba alternativa|barrios de bogota|periodico|comunitari|adn") ~ "Prensa Local y Comunitaria",
      TRUE ~ "Prensa Digital General"
    )
  )

# 6.2 MEJORA 2: Validacion de mencion territorial en el texto y confianza geografica
# Comprueba si el titular o el resumen mencionan explicitamente la localidad o sus barrios representativos
df_patrones_territorio <- tibble(
  localidad = localidades_bogota,
  patron_geografico = c(
    "usaquen|cedritos|santa barbara|san cristobal norte|torca|unicentro",
    "chapinero|chico|rosales|el retiro|lago|marly|antiguo country",
    "santa fe|la macarena|las aguas|germania|las nieves|san victorino|la perseverancia",
    "san cristobal|20 de julio|la victoria|libertadores|quindio",
    "usme|yomasa|alfonso lopez|danubio|monteblanco",
    "tunjuelito|venecia|san carlos|tunal|el tunal|san benito",
    "bosa|brasil|carbonell|porvenir|san bernardino|la libertad",
    "kennedy|patio bonito|castilla|tintal|el tintal|corabastos|mandalay|carvajal|timiza",
    "fontibon|modelia|salitre|capellania|zona franca|san pablo",
    "engativa|minuto de dios|boyaca real|alamos|quirigua|garces navas",
    "suba|rincon|niza|colina campestre|tibabuyes|prado veraniego|pontevedra|la campina",
    "barrios unidos|7 de agosto|siete de agosto|polo club|doce de octubre|rincon del salitre|la castellana",
    "teusaquillo|palermo|galerias|salitre greco|parkway|ciudad salitre|la soledad",
    "los martires|martires|santa isabel|ricaurte|eduardo santos|la sabana|voto nacional",
    "antonio narino|antonio nariño|restrepo|santander|policarpa|ciudad berna",
    "puente aranda|ciudad montes|salazar gomez|gorgonzola|cundinamarca",
    "candelaria|la candelaria|centro historico|plaza de bolivar|belen",
    "rafael uribe|olaya|quiroga|san jose|diana turbay|marruecos",
    "ciudad bolivar|meissen|sierra morena|arborizadora|lucero|san francisco|jerusalen"
  )
) |>
  mutate(loc_slug = tolower(stri_trans_general(localidad, "Latin-ASCII")))

df_muestra_enriquecida <- df_muestra_enriquecida |>
  mutate(loc_slug = tolower(stri_trans_general(localidad, "Latin-ASCII"))) |>
  left_join(df_patrones_territorio |> select(loc_slug, patron_geografico), by = "loc_slug") |>
  mutate(
    texto_geografia      = tolower(stri_trans_general(paste(titulo, resumen), "Latin-ASCII")),
    menciona_territorio  = str_detect(texto_geografia, patron_geografico),
    confianza_geografica = if_else(menciona_territorio, "Alta", "Media")
  ) |>
  select(-loc_slug, -patron_geografico, -texto_geografia)

# 6.3 MEJORA 3: Diccionario semantico exhaustivo de delitos y hechos de seguridad
# Normalizacion de texto sin tildes para optimizar busquedas lexicograficas
texto_corpus <- tolower(stri_trans_general(paste(df_muestra_enriquecida$titulo, df_muestra_enriquecida$resumen), "Latin-ASCII"))

# Diccionarios semanticos expandidos por modalidad:
patron_violencia <- "arma de fuego|pistola|revolver|cuchillo|arma blanca|punzon|punal|disparo|disparos|balacera|tiroteo|baleado|apunalado|herido|homicidio|asesinato|asesinado|asesino|sicariato|sicario|muerto|cadaver|embolsado|abatido|abatidos|cruces de disparos|lesiones personales|muerte|violenta|mataron"

patron_personas  <- "celular|telefono|movil|peaton|transeunte|atraco|atracaron|asaltaron|raponazo|cosquilleo|pasajero|transmilenio|sitp|paradero|billetera|reloj|joya|bolso|mochila|morral|paseo millonario|taxista|fleteo|transeuntes|manada|hurto a personas|robo a personas|ladron de celular|robaron a"

patron_comercio  <- "local|comercio|tienda|restaurante|panaderia|bodega|negocio|supermercado|almacen|banco|cajero|joyeria|establecimiento|farmacia|drogueria|comerciante|comerciantes|asaltaron local|salon de belleza|peluqueria|bar|discoteca|asadero"

patron_residencias <- "casa|apartamento|vivienda|conjunto residencial|edificio|habitacion|residencia|apartamentero|apartamenteros|hurto a residencia|robo a casa"

patron_vehiculos <- "carro|vehiculo|moto|motocicleta|camioneta|autopartes|llanta|espejo|computador del carro|bici|bicicleta|ciclista|bicitaxi|deshuesadero|hurto de automotores|halado|taxi"

patron_infraestructura <- "cable|cables|medidor|medidores|alcantarilla|tapas de alcantarilla|alumbrado publico|infraestructura|fibra optica|energia|acueducto|residuos|basuras"

patron_extorsion <- "extorsion|extorsiones|vacuna|vacunas|gota a gota|panfleto|panfletos|amenaza|amenazas|boleteo|chantaje|tren de aragua|satanas|milicias"

patron_microtrafico <- "estupefacientes|microtrafico|droga|drogas|olla|ollas|papeleta|papeletas|dosis|bazuco|marihuana|cocaina|jibaro|jibaros|expendedor|expendedores|trafico de estupefacientes|narco"

patron_operativos <- "capturado|capturada|capturados|capturan|cayo|cayeron|banda|bandas|desarticulada|desarticulan|allanamiento|allanamientos|operativo|golpe a|desmantelan|judicializados|cayeron los|detuvieron|detenido|detenidos|aprehendido|aprehendidos|incautaron|incautacion|porte ilegal|porte de armas|mini uzi|falsificacion|licor adulterado"

patron_politica   <- "frente de seguridad|frentes de seguridad|camaras|camara|pie de fuerza|policias|dispositivo|comando|comandos|seguridad en navidad|alcaldesa|alcalde|patrullaje|patrullajes|cifras de seguridad|consejo de seguridad|vigilancia|estrategia de seguridad|percepcion de inseguridad|victimizacion|cifras|dane|secretaria de seguridad|seguridad en bogota|falta de seguridad"

patron_fraude     <- "estafa|estafas|ciberdelito|ciberdelitos|falso servicio|suplantacion|engano|clonacion|lucrando"

df_muestra_enriquecida <- df_muestra_enriquecida |>
  mutate(
    # Variables indicadoras binarias por dimension
    modalidad_personas       = str_detect(texto_corpus, patron_personas),
    modalidad_comercio       = str_detect(texto_corpus, patron_comercio),
    modalidad_residencias    = str_detect(texto_corpus, patron_residencias),
    modalidad_automotores    = str_detect(texto_corpus, patron_vehiculos),
    delito_con_violencia     = str_detect(texto_corpus, patron_violencia),
    modalidad_extorsion      = str_detect(texto_corpus, patron_extorsion),
    modalidad_microtrafico   = str_detect(texto_corpus, patron_microtrafico),
    modalidad_operativos     = str_detect(texto_corpus, patron_operativos),
    modalidad_prevencion     = str_detect(texto_corpus, patron_politica),
    
    # Clasificacion tematica dominante exhaustiva
    tipo_delito_dominante    = case_when(
      str_detect(texto_corpus, patron_violencia) & str_detect(texto_corpus, patron_personas) ~ "Hurto a personas con violencia",
      str_detect(texto_corpus, patron_personas)        ~ "Hurto a personas",
      str_detect(texto_corpus, patron_comercio)       ~ "Hurto a comercio",
      str_detect(texto_corpus, patron_vehiculos)      ~ "Hurto de vehiculos / autopartes / bicicletas",
      str_detect(texto_corpus, patron_residencias)    ~ "Hurto a residencias",
      str_detect(texto_corpus, patron_extorsion)      ~ "Extorsion y amenazas",
      str_detect(texto_corpus, patron_microtrafico)   ~ "Microtrafico y estupefacientes",
      str_detect(texto_corpus, patron_infraestructura)~ "Hurto de infraestructura y servicios publicos",
      str_detect(texto_corpus, patron_violencia)      ~ "Hecho violento y homicidio",
      str_detect(texto_corpus, patron_operativos)     ~ "Operativos policiales y captura de bandas",
      str_detect(texto_corpus, patron_politica)       ~ "Politica de seguridad, vigilancia y prevencion",
      str_detect(texto_corpus, patron_fraude)         ~ "Fraude, estafa y cibercrimen",
      str_detect(texto_corpus, "hurto|robo|atraco|ladron|ladrones|delincuente|delincuentes|asaltante") ~ "Hurto y delincuencia comun general",
      TRUE                                            ~ "Seguridad ciudadana y coyuntura no especificada"
    )
  )

# 6.4 MEJORA 4: Variables de calendario y estructura de panel econometrico
df_muestra_final <- df_muestra_enriquecida |>
  mutate(
    año        = year(fecha_chunk_desde),
    mes        = month(fecha_chunk_desde),
    año_mes    = format(fecha_chunk_desde, "%Y-%m"),
    trimestre  = paste0(year(fecha_chunk_desde), "-T", quarter(fecha_chunk_desde)),
    semana_año = isoweek(fecha_chunk_desde)
  ) |>
  arrange(localidad, fecha_chunk_desde)


# ------------------------------------------------------------------------------
# 7. ALMACENAMIENTO DE MICRODATOS Y METADATOS MUESTRALES
# ------------------------------------------------------------------------------

# 7.1 Exportacion columnar definitiva a Parquet
write_parquet(df_muestra_final, archivo_consolidado)

# 7.2 Exportacion en formato nativo serializado de R (.rds)
saveRDS(df_muestra_final, archivo_consol_rds)

# 7.3 Generacion y serializacion de metadatos de auditoria muestral (JSON)
tabla_cobertura <- df_muestra_final |>
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
  total_filas_consolidadas = nrow(df_muestra_final),
  rango_generalizable      = list(
    inicio = as.character(min(df_muestra_final$fecha_chunk_desde, na.rm = TRUE)),
    fin    = as.character(max(df_muestra_final$fecha_chunk_desde, na.rm = TRUE))
  ),
  localidades              = split(tabla_cobertura, seq_len(nrow(tabla_cobertura)))
)

write_json(metadatos_auditoria, archivo_cobertura, pretty = TRUE, auto_unbox = TRUE)


# ------------------------------------------------------------------------------
# 8. RESUMEN DESCRIPTIVO DE LA MUESTRA PROCESADA
# ------------------------------------------------------------------------------

# Cuadro 1: Distribucion anual de notas periodisticas
conteo_anual <- df_muestra_final |>
  count(año, name = "articulos") |>
  as.data.frame()

# Cuadro 2: Distribucion por categoria de medio de comunicacion
conteo_tipo_medio <- df_muestra_final |>
  count(tipo_medio, sort = TRUE, name = "articulos") |>
  as.data.frame()

# Cuadro 3: Distribucion por modalidad delictiva dominante (taxonomia refinada)
conteo_delitos <- df_muestra_final |>
  count(tipo_delito_dominante, sort = TRUE, name = "articulos") |>
  as.data.frame()

# Cuadro 4: Nivel de confianza geografica territorial
conteo_geografia <- df_muestra_final |>
  count(confianza_geografica, name = "articulos") |>
  as.data.frame()

# Cuadro 5: Auditoria de valores faltantes (NA) en campos criticos
valores_faltantes <- data.frame(
  variable = c("titulo", "resumen", "enlace", "cuerpo", "tipo_medio", "tipo_delito_dominante", "año_mes"),
  nulos    = c(
    sum(is.na(df_muestra_final$titulo)),
    sum(is.na(df_muestra_final$resumen)),
    sum(is.na(df_muestra_final$enlace)),
    sum(is.na(df_muestra_final$cuerpo)),
    sum(is.na(df_muestra_final$tipo_medio)),
    sum(is.na(df_muestra_final$tipo_delito_dominante)),
    sum(is.na(df_muestra_final$año_mes))
  )
)

print(conteo_anual, row.names = FALSE)
print(conteo_tipo_medio, row.names = FALSE)
print(conteo_delitos, row.names = FALSE)
print(conteo_geografia, row.names = FALSE)
print(valores_faltantes, row.names = FALSE)
