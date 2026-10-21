# ==============================================================================
# poblacion_localidades.R
# Entra : API CKAN de Datos Abiertos Bogotá (dataset "piramide-poblacional-
#         bogota-d-c", recurso "Población en Bogotá D.C por Localidad")
# Resuelve: descarga reproducible de la población por localidad, año, sexo y edad
# Produce : data/raw/poblacion_localidades_raw.parquet
# Fuente  : https://datosabiertos.bogota.gov.co (consulta: 19-oct-2026)
# ==============================================================================

# 1. Configuración ----
rm(list = ls())
options(scipen = 999)
set.seed(20261014)

library(here)
library(conflicted)
library(httr)
library(jsonlite)
library(dplyr)
library(arrow)

conflict_prefer("filter", "dplyr")  # función no vista en clase: conflict_prefer
conflict_prefer("lag", "dplyr")
conflict_prefer("select", "dplyr")

## 1.1 Constantes ----
url_api <- "https://datosabiertos.bogota.gov.co/api/3/action"
slug_dataset <- "piramide-poblacional-bogota-d-c"
ruta_salida <- here("data", "raw", "poblacion_localidades_raw.parquet")
limite_pagina <- 30000

# 2. Ficha del dataset ----
# Entra: slug del dataset. Sale: lista de recursos (archivos) con su metadata.
# Por qué: el resource_id cambió entre publicaciones, así que se busca por nombre.
resp_ficha <- GET(
  paste0(url_api, "/package_show"),
  query = list(id = slug_dataset),
  timeout(60)
)  # función no vista en clase: GET, timeout
stopifnot(status_code(resp_ficha) == 200)

ficha <- fromJSON(
  content(resp_ficha, as = "text", encoding = "UTF-8"),
  simplifyVector = FALSE
)  # función no vista en clase: content, fromJSON
stopifnot(isTRUE(ficha$success))

campo <- function(x, nombre) {
  if (is.null(x[[nombre]])) NA_character_ else as.character(x[[nombre]])
}

tabla_recursos <- tibble(
  id = sapply(ficha$result$resources, function(r) campo(r, "id")),
  nombre = sapply(ficha$result$resources, function(r) campo(r, "name")),
  formato = sapply(ficha$result$resources, function(r) campo(r, "format")),
  modificado = sapply(ficha$result$resources, function(r) {
    campo(r, "last_modified")
  }),
  datastore = sapply(ficha$result$resources, function(r) {
    isTRUE(r$datastore_active)
  })
)
print(tabla_recursos, width = Inf)

# 3. Elegir el recurso de localidad ----
candidatos <- tabla_recursos |>
  filter(datastore, formato == "CSV",
         grepl("Localidad", nombre, ignore.case = TRUE),
         !grepl("UPZ", nombre, ignore.case = TRUE))
stopifnot(nrow(candidatos) >= 1)

recurso_id <- candidatos |>
  arrange(desc(modificado)) |>
  slice(1) |>
  pull(id)
message("Recurso elegido: ", recurso_id, " (candidatos: ", nrow(candidatos), ")")

# 4. Descarga paginada con datastore_search ----
# Por qué: la API entrega un máximo de filas por llamada; se pide por bloques.
pedir_pagina <- function(offset) {
  r <- GET(
    paste0(url_api, "/datastore_search"),
    query = list(resource_id = recurso_id, limit = limite_pagina,
                 offset = offset),
    timeout(120)
  )
  stopifnot(status_code(r) == 200)
  fromJSON(content(r, as = "text", encoding = "UTF-8"))
}

primera <- pedir_pagina(0)
total_filas <- primera$result$total
bloques <- list(primera$result$records)
offset <- limite_pagina
while (offset < total_filas) {
  bloques[[length(bloques) + 1]] <- pedir_pagina(offset)$result$records
  offset <- offset + limite_pagina
}

poblacion_01_raw <- bind_rows(bloques)
stopifnot(nrow(poblacion_01_raw) == total_filas)
message("Filas descargadas: ", nrow(poblacion_01_raw))

# 5. Guardar en data/raw ----
dir.create(here("data", "raw"), showWarnings = FALSE, recursive = TRUE)
write_parquet(poblacion_01_raw, ruta_salida)
stopifnot(file.exists(ruta_salida))
message("Guardado: ", ruta_salida)

# 6. Inspección (pegarme el resultado) ----
# Entra: poblacion_01_raw (tal como llegó de la API, sin limpiar).
# Resuelve: ver columnas, años, localidades, sexo y grupos de edad reales.
# Produce: solo salida en consola; no modifica datos ni guarda archivos.
glimpse(poblacion_01_raw)
print(count(poblacion_01_raw, ANO))
print(count(poblacion_01_raw, CODIGO_LOCALIDAD, NOMBRE_LOCALIDAD))
print(count(poblacion_01_raw, SEXO))
print(count(poblacion_01_raw, GRUPOEDAD))

# 7. Verificaciones del Hito 1 ----
# Entra: poblacion_01_raw (sin limpiar).
# Resuelve: comprobar que están las 19 localidades urbanas y los años
#   2022-2025, y que POBLACION se puede convertir a número.
# Produce: solo controles (stopifnot) y una tabla de control en consola.

## 7.1 Cobertura de localidades y años ----
codigos_urbanos <- as.character(1:19)
stopifnot(all(codigos_urbanos %in% unique(poblacion_01_raw$CODIGO_LOCALIDAD)))
stopifnot(all(as.character(2022:2025) %in% unique(poblacion_01_raw$ANO)))

## 7.2 POBLACION convertible a número ----
stopifnot(!anyNA(suppressWarnings(as.numeric(poblacion_01_raw$POBLACION))))

## 7.3 Control: total de Bogotá vs. suma de localidades ----
# Por qué: el código "0" es el total de la ciudad; si coincide con la suma
# de las localidades, no hay filas faltantes ni duplicadas.
control_total <- poblacion_01_raw |>
  mutate(poblacion_num = as.numeric(POBLACION)) |>
  filter(ANO %in% as.character(2022:2025)) |>
  group_by(ANO) |>
  summarise(
    total_bogota = sum(poblacion_num[CODIGO_LOCALIDAD == "0"]),
    suma_localidades = sum(poblacion_num[CODIGO_LOCALIDAD != "0"]),
    .groups = "drop"
  ) |>
  mutate(diferencia = total_bogota - suma_localidades)
print(control_total)
message("Verificaciones de población completadas.")