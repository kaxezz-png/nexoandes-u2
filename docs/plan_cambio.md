# Plan de cambio y recuperación · AWS (E04)

> Plan declarado y commiteado **antes** de ejecutar el cambio v1 → v2 (la hora del commit lo acredita). Estado previo registrado el 2026-11-21 07:12 UTC.

## 1. Versiones y artefactos

| Elemento | v1 (actual / retorno) | v2 (objetivo) |
|---|---|---|
| Artefacto | `templates/user_data_u2.sh.tpl` con `portal_version = v1` (perfil `basic`) | misma plantilla con `portal_version = v2` (perfil `extended`) |
| Commit (build_ref) | `fc6dd14623f0` (pipeline #6) | el commit que cambia `app_version` a `v2` |
| Launch Template | `na-u2-c50-a007-lt` versión `3` | versión `4` (la crea el apply) |
| AMI | `ami-012cadcb0ec2f554f` (Ubuntu 22.04, fijada en u2.auto.tfvars) | la misma |
| SHA-256 del artefacto (Portal) | `82f7e3a976f7ec7b46f739244e44e47b59a73aa840e0269870d3b0f42e1fd7fa` | distinto (perfil `extended`), se registra después del cambio |
| Grupo EC2 activo | `na-u2-c50-a007-asg-lt3`: `i-009f97073ffac58d9`, `i-027d0dd51fad1ff83` | `na-u2-c50-a007-asg-lt4` con 2 instancias nuevas |
| Endpoint (no cambia) | `http://na-u2-c50-a007-alb-1049577402.us-east-1.elb.amazonaws.com` | el mismo |

**Inmutabilidad:** las instancias no se modifican. Cada versión es una nueva versión del Launch Template y el ASG reemplaza las instancias completas. **Persistencia:** el Portal no guarda datos de negocio; la caché de metadata vive en memoria y se pierde al reemplazar, lo cual es esperado. El disco de cada instancia es descartable.

## 2. Estrategias comparadas

| Criterio | Rolling con Instance Refresh | Blue-green por grupo EC2 (elegida) | Canary (pesos en el listener) |
|---|---|---|---|
| Capacidad extra | Hasta 2 instancias más | Un grupo nuevo completo (2) mientras conviven | Segundo grupo completo |
| Controlador | ASG (Instance Refresh) | Terraform: crea el grupo nuevo, espera destinos sanos y destruye el anterior | Listener con pesos + dos grupos |
| Recuperación | Rollback de un refresh activo, o refresh hacia v1 | Otra operación hacia v1 con el mismo mecanismo | Volver el peso a 0 % |
| Viabilidad en el Learner Lab | **No viable**: la SCP niega `autoscaling:StartInstanceRefresh` (AccessDenied) | Viable: solo usa crear y borrar grupos | Viable, pero más compleja y sin métricas |
| Riesgo | Conviven v1 y v2 | Conviven v1 y v2 hasta retirar el grupo anterior | Requiere métricas para decidir |

**Decisión:** blue-green por grupo EC2, con `create_before_destroy`. El nombre del grupo incluye la versión del Launch Template; al cambiar la versión, Terraform crea un grupo nuevo en el mismo target group, espera `min_elb_capacity = 2` destinos sanos y recién entonces destruye el grupo anterior (drenaje de 30 s). **Qué cambió la decisión:** el plan original era rolling con Instance Refresh, pero el ensayo #4 falló con AccessDenied por la política del laboratorio. En una cuenta sin esa restricción, Instance Refresh sería preferible por usar menos capacidad temporal.

## 3. Capacidad

- **Base:** 2 instancias (`min = max = deseada = 2`), una por zona.
- **Temporal:** el grupo nuevo agrega 2 instancias: hasta 4 durante el cambio.
- **Mínimo sano:** el grupo anterior no se retira hasta que el nuevo tenga 2 destinos sanos en el ALB.

## 4. Aceptación

Se acepta el cambio si se cumplen **todas**:

1. Ventana completa: desde inicio − 60 s hasta estabilización + 120 s, sin brechas mayores de 7 s.
2. Cero fallos funcionales: ningún timeout, error, HTTP distinto de 200 ni identidad/versión incorrecta.
3. Durante la transición se admiten v1 y v2; después de estabilizar, solo v2.
4. Terraform termina el apply: grupo nuevo con 2 destinos sanos y grupo anterior destruido.
5. Capacidad comprobada: siempre al menos 2 destinos `healthy` en las consultas cada 20 s.
6. Al final, todas las instancias en servicio usan la nueva versión del Launch Template y son IDs distintos a los de v1.

**Inicio:** hora "Inicio apply (UTC)" del job de apply, en el resumen del pipeline.
**Estabilización:** hora en que `esperar_refresh.sh` confirma un solo grupo activo, destinos sanos y v2 en las 20 muestras.

## 5. Señales de fallo y detención

| Señal | Acción |
|---|---|
| Una instancia nueva no pasa el health check del ALB | Terraform no destruye el grupo anterior (v1 sigue atendiendo). A los 15 min el apply falla; se analiza y se ejecuta la recuperación. |
| Fallo HTTP en la observación | Se registra, no se borra. El ensayo no cumple la aceptación: se corrige y se repite completo. |
| Capacidad sana menor a 2 | Se detiene el cambio y se ejecuta la recuperación. |
| Apply en error | Se ejecuta la recuperación hacia v1. |

## 6. Recuperación (E07)

- **Mecanismo:** reversión planificada a v1 mediante una operación nueva: PR con `app_version = "v1"` y pipeline `apply`. Eso crea otra versión del Launch Template con el artefacto v1 y un grupo EC2 nuevo, con el mismo blue-green.
- **Diferencia con rollback:** no hay rollback de una operación activa (Instance Refresh está denegado en el laboratorio); es un retorno con otra operación.
- **Requisitos:** AMI fijada, commit v1 conocido y misma plantilla.
- **Observación:** mismo protocolo. Versión objetivo: v1. Admitidas en la transición: v2 y v1.
- **Reconciliación:** después de recuperar, `plan` con el mismo commit debe decir "No changes". No se edita el state.

## 7. Herramientas de observación

- `scripts/observar_http.sh`: `/api/check` cada 2 s, timeout 5 s, sin reintentos.
- `scripts/observar_capacidad.sh`: todos los grupos EC2 del alumno y los destinos, cada 20 s.
- `scripts/esperar_refresh.sh` (pipeline): resultado real del controlador.
- `scripts/analizar_ventana.sh`: apoyo; se contrasta con los registros del proveedor.

**Límite del muestreo:** las muestras prueban lo que ocurrió en los instantes observados, no lo que ocurrió entre ellas.

## 8. Autorización

El plan de Terraform de cada operación se revisa y se aprueba en el environment `u2-aprobacion` de GitHub Actions. La aprobación corresponde al commit que muestra el resumen del plan, a `u2.auto.tfvars` de ese commit y al contexto AWS `us-east-1`.
