# Aplicación interactiva en Shiny

En esta carpeta está el código del tablero interactivo en R Shiny que presentaremos en la Entrega Final (Semana 16, 15% de la nota).

---

## 1. Qué hace la aplicación

* **Diseño:** Construida con [`bslib`](https://rstudio.github.io/bslib/) (Bootstrap 5, tema `flatly`) para que se vea moderna y funcione bien en cualquier pantalla.
* **Qué puedes explorar en el tablero:**
  * **Filtros interactivos:** Puedes seleccionar el año (2022 a 2025), la localidad y el tipo de hurto (personas, residencias o motos).
  * **Tarjetas de resumen:** Muestran cifras clave como el total de localidades analizadas, el sentimiento promedio de las noticias y el número de grupos formados con $K$-means.
  * **Mapas y gráficos por localidad:** Muestran las tasas de delito y a qué grupo de inseguridad pertenece cada localidad.
  * **Gráficos de sentimiento:** Comparan si en las zonas con más hurtos las noticias tienen un tono más negativo.
  * **Explorador de noticias:** Una tabla interactiva para buscar y filtrar titulares y notas.

---

## 2. De dónde toma los datos la app

La aplicación lee directamente el archivo consolidado que genera el pipeline:
```text
data/processed/datos_consolidados_shiny.rds
```
*(Si todavía no has corrido el pipeline y ese archivo no existe, no te preocupes: `app.R` trae unos datos de ejemplo para que puedas abrir y ver la interfaz sin errores).*

---

## 3. Cómo correr la app en RStudio

Desde la consola de RStudio en la raíz del proyecto:
```r
shiny::runApp(here::here("app"))
```

O abre el archivo [`app/app.R`](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/app/app.R) y haz clic en el botón **Run App**.
