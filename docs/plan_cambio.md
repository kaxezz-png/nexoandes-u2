# Plan de cambio y recuperación · AWS (E04)

> Borrador: completa los campos `<...>` con tus valores reales y deja este archivo commiteado **antes** de ejecutar el cambio. El commit con hora es la prueba de que el plan es previo.

## 1. Versiones y artefactos

| Elemento | v1 (actual / retorno) | v2 (objetivo) |
|---|---|---|
| Artefacto | `templates/user_data_u2.sh.tpl` con `portal_version = v1` (perfil `basic`) | misma plantilla con `portal_version = v2` (perfil `extended`) |
| Commit (build_ref) | `<sha-v1>` | `<sha-v2>` |
| Launch Template | `na-u2-c50-a007-lt` versión `<n>` | versión `<n+1>` (la crea el apply) |
| AMI | `<ami-id fijado en u2.auto.tfvars>` | la misma |
| SHA-256 del artefacto (Portal) | `<hash v1>` | `<hash v2>` |

**Inmutabilidad:** las instancias no se modifican. Cada versión es una nueva versión del Launch Template y el ASG reemplaza las instancias completas. **Persistencia:** el Portal no guarda datos de negocio; la caché de metadata vive en memoria y se pierde al reemplazar, lo cual es esperado. El disco de cada instancia es descartable.

## 2. Estrategias comparadas

| Criterio | Rolling con Instance Refresh (elegida) | Blue-green (dos ASG + cambio en el listener) | Canary (pesos en el listener) |
|---|---|---|---|
| Capacidad extra | Temporal: hasta 2 instancias más durante el cambio | Duplica la flota completa mientras conviven | Duplica o requiere un segundo grupo |
| Controlador | Uno: el ASG | Terraform + listener (dos piezas) | Listener con pesos + dos grupos |
| Recuperación | Otro refresh hacia v1, o rollback de un refresh activo | Volver el listener al grupo azul (muy rápida) | Volver el peso a 0 % |
| Complejidad en Terraform | Baja: un bloque `instance_refresh` | Media/alta | Alta |
| Costo y cuotas del laboratorio | Bajo | Mayor | Mayor |
| Riesgo | Conviven v1 y v2 durante la transición | Corte en el instante del cambio de listener si el verde no está sano | Requiere métricas que el laboratorio no tiene |

**Decisión:** rolling con Instance Refresh, porque cumple el reemplazo inmutable con un único controlador, la menor capacidad temporal y la menor complejidad en un laboratorio con cuotas limitadas. **Qué cambiaría la decisión:** si se exigiera volver atrás en segundos sin crear instancias nuevas, blue-green sería mejor, a cambio de mantener dos flotas.

## 3. Capacidad

- **Base:** 2 instancias (`min = max = deseada = 2`), una por zona.
- **Temporal:** `max_healthy_percentage = 200` permite hasta 4 instancias durante el refresh.
- **Mínimo sano:** `min_healthy_percentage = 100`: nunca menos de 2 instancias sanas en servicio.

## 4. Aceptación

Se acepta el cambio si se cumplen **todas**:

1. Ventana completa: desde inicio − 60 s hasta estabilización + 120 s, sin brechas mayores de 7 s.
2. Cero fallos funcionales: ningún timeout, error, HTTP distinto de 200 ni identidad/versión incorrecta.
3. Durante la transición se admiten v1 y v2; después de estabilizar, solo v2.
4. El Instance Refresh termina en `Successful`.
5. Capacidad comprobada: siempre al menos 2 destinos `healthy` en las consultas cada 20 s.
6. Al final, todas las instancias en servicio usan la nueva versión del Launch Template y son IDs distintos a los de v1.

**Inicio:** hora en que el job de apply inicia el refresh (registrada en el resumen del pipeline).
**Estabilización:** hora en que `esperar_refresh.sh` confirma `Successful`, destinos sanos y v2 en las 20 muestras.

## 5. Señales de fallo y detención

| Señal | Acción |
|---|---|
| Una instancia nueva no pasa el health check del ALB | El refresh no avanza (min 100 %): las instancias v1 siguen atendiendo. Si en 15 min no avanza → se cancela el refresh (`cancel-instance-refresh`) y se analiza. |
| Fallo HTTP en la observación | Se registra, no se borra. El ensayo no cumple la aceptación: se corrige y se repite completo. |
| Capacidad sana menor a 2 | Se detiene el cambio y se ejecuta la recuperación. |
| Refresh en `Failed` | Se ejecuta la recuperación hacia v1. |

## 6. Recuperación (E07)

- **Mecanismo:** reversión planificada a v1 mediante una operación nueva: PR con `app_version = "v1"` y pipeline `apply`. Eso crea otra versión del Launch Template con el artefacto v1 y un nuevo Instance Refresh.
- **Diferencia con rollback:** `rollback-instance-refresh` solo aplica a un refresh **activo**. Aquí v2 ya terminó, así que se trata de un retorno con otra operación.
- **Requisitos:** AMI fijada, commit v1 conocido y misma plantilla.
- **Observación:** mismo protocolo. Versión objetivo: v1. Admitidas en la transición: v2 y v1.
- **Reconciliación:** después de recuperar, `plan` con el mismo commit debe decir "No changes". No se edita el state.

## 7. Herramientas de observación

- `scripts/observar_http.sh`: `/api/check` cada 2 s, timeout 5 s, sin reintentos.
- `scripts/observar_capacidad.sh`: ASG, Instance Refresh y destinos cada 20 s.
- `scripts/esperar_refresh.sh` (pipeline): resultado real del controlador.
- `scripts/analizar_ventana.sh`: apoyo; se contrasta con los registros del proveedor.

**Límite del muestreo:** las muestras prueban lo que ocurrió en los instantes observados, no lo que ocurrió entre ellas.

## 8. Autorización

El plan de Terraform de cada operación se revisa y se aprueba en el environment `u2-aprobacion` de GitHub Actions. La aprobación corresponde al commit `<sha>`, a `u2.auto.tfvars` de ese commit y al contexto AWS `us-east-1`.
