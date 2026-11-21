#!/usr/bin/env bash
# Observador de capacidad y controlador (protocolo U2): cada 20 s (maximo exigido: 30 s).
# Registra TODOS los grupos EC2 del alumno (durante el cambio conviven el grupo
# anterior y el nuevo) y la salud de los destinos del ALB.
#
# Uso: scripts/observar_capacidad.sh <ARN-target-group> [prefijo-archivo]
# Genera <prefijo>.csv (resumen) y <prefijo>.log (detalle JSON). Ctrl+C para detener.

set -u
TG="${1:?Uso: $0 <TG-ARN> [prefijo]}"
PREFIJO="${2:-evidencias/capacidad_$(date -u +%Y%m%dT%H%M%SZ)}"
INTERVALO=20

mkdir -p "$(dirname "$PREFIJO")"
CSV="$PREFIJO.csv"; LOG="$PREFIJO.log"
echo "utc,grupos(nombre:deseada:inservice_healthy:lt_version),targets_healthy,targets_total,targets" > "$CSV"
trap 'echo; echo "Registro en $CSV y $LOG"; exit 0' INT TERM
echo "Consultando grupos del alumno a007 y destinos cada ${INTERVALO} s. Ctrl+C para detener."

while true; do
  t0="$(date +%s)"; utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  grupos="$(aws autoscaling describe-auto-scaling-groups --filters "Name=tag:alumno,Values=a007" \
    --query 'AutoScalingGroups[].join(`:`, [AutoScalingGroupName, to_string(DesiredCapacity), to_string(length(Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`])), LaunchTemplate.Version])' \
    --output text 2>&1 | tr '\t' ';')"
  tg="$(aws elbv2 describe-target-health --target-group-arn "$TG" \
    --query '[length(TargetHealthDescriptions[?TargetHealth.State==`healthy`]),length(TargetHealthDescriptions),join(`;`, TargetHealthDescriptions[].join(`:`, [Target.Id, TargetHealth.State]))]' \
    --output text 2>&1 | tr '\t' ',')"
  echo "$utc,$grupos,$tg" >> "$CSV"
  {
    echo "=== $utc ==="
    aws autoscaling describe-auto-scaling-groups --filters "Name=tag:alumno,Values=a007" \
      --query 'AutoScalingGroups[].{grupo:AutoScalingGroupName,deseada:DesiredCapacity,lt:LaunchTemplate,instancias:Instances[].{id:InstanceId,az:AvailabilityZone,estado:LifecycleState,salud:HealthStatus,lt_version:LaunchTemplate.Version}}' --output json
    aws elbv2 describe-target-health --target-group-arn "$TG" --output json
  } >> "$LOG" 2>&1
  echo "  $utc | grupos: $grupos | targets: $tg"
  resto=$(( INTERVALO - ($(date +%s) - t0) )); [ "$resto" -gt 0 ] && sleep "$resto"
done
