# Aplicativo Interactivo Shiny

Esta carpeta contiene el tablero analítico desarrollado en R Shiny para la Entrega Final (Semana 16, 15%).

---

## 1. Características del Aplicativo

* **Framework UI:** Construido con [`bslib`](https://rstudio.github.io/bslib/) (Bootstrap 5, tema `flatly`) para un diseño responsivo y moderno.
* **Componentes Principales:**
  * **Barra lateral de control:** Filtros interactivos por año (2022–2025), localidad y modalidad de delito (personas, residencias, motos).
  * **Tarjetas de resumen (`value_box`):** Indicadores agregados clave de cobertura, polaridad promedio y clústeres.
  * **Mapa y perfiles espaciales:** Visualización de tasas delictivas y asignación no supervisada $K$-means por localidad.
  * **Sentimiento mediático:** Gráficos de correlación entre criminalidad registrada y polaridad de noticias (`sentometrics`).
  * **Explorador de noticias:** Tabla interactiva filtrable construida con `DT`.

---

## 2. Insumos y Datos

La aplicación consume el objeto unificado preparado por el pipeline:
```text
data/processed/datos_consolidados_shiny.rds
```
*(Si este archivo aún no ha sido compilado, `app.R` incorpora un conjunto de datos fallback de demostración para permitir la previsualización del layout).*

---

## 3. Instrucciones de Ejecución

Desde la consola de RStudio en la raíz del proyecto:
```r
shiny::runApp(here::here("app"))
```

O abriendo [`app/app.R`](file:///Users/juanjoseecheverry/Library/Mobile%20Documents/com~apple~CloudDocs/Universidad/Maestria%20%28MECA%29/Primer%20semestre/Taller%20R/Repo_Entrega_Final_Taller_R/app/app.R) y haciendo clic en **Run App**.
