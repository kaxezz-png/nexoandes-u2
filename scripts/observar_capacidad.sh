#!/usr/bin/env bash
# Observador de capacidad y controlador (protocolo U2): una consulta cada 20 s
# (maximo exigido: 30 s). Cada consulta corre en segundo plano y sus llamadas
# a AWS van en paralelo: aunque AWS CLI tarde varios segundos en Windows, la
# cadencia se mantiene. Registra TODOS los grupos EC2 del alumno (durante el
# cambio conviven el grupo anterior y el nuevo) y la salud de los destinos.
#
# Uso: scripts/observar_capacidad.sh <ARN-target-group> [prefijo-archivo]
# Genera <prefijo>.csv (una linea por consulta) y <prefijo>.log (detalle JSON).

set -u
export TZ=UTC
TG="${1:?Uso: $0 <TG-ARN> [prefijo]}"
PREFIJO="${2:-evidencias/capacidad_$(date -u +%Y%m%dT%H%M%SZ)}"
INTERVALO=20

mkdir -p "$(dirname "$PREFIJO")"
CSV="$PREFIJO.csv"; LOG="$PREFIJO.log"; TMP="$PREFIJO.tmp"
mkdir -p "$TMP"
echo "consulta_utc,grupos(nombre:deseada:inservice_healthy:lt_version),targets_healthy,targets_total,targets" > "$CSV"

cerrar() {
  echo; echo "Esperando consultas en curso..."; wait
  for f in $(ls "$TMP"/*.json 2>/dev/null | sort); do cat "$f" >> "$LOG"; done
  rm -rf "$TMP"
  echo "Registro en $CSV y $LOG"; exit 0
}
trap cerrar INT TERM

consulta() {
  local utc="$1" d="$TMP/$1"
  aws autoscaling describe-auto-scaling-groups --filters "Name=tag:alumno,Values=a007" \
    --query 'AutoScalingGroups[].join(`:`, [AutoScalingGroupName, to_string(DesiredCapacity), to_string(length(Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`])), LaunchTemplate.Version])' \
    --output text > "$d.g" 2>&1 &
  aws elbv2 describe-target-health --target-group-arn "$TG" \
    --query '[length(TargetHealthDescriptions[?TargetHealth.State==`healthy`]),length(TargetHealthDescriptions),join(`;`, TargetHealthDescriptions[].join(`:`, [Target.Id, TargetHealth.State]))]' \
    --output text > "$d.t" 2>&1 &
  {
    echo "=== $utc ==="
    aws autoscaling describe-auto-scaling-groups --filters "Name=tag:alumno,Values=a007" \
      --query 'AutoScalingGroups[].{grupo:AutoScalingGroupName,deseada:DesiredCapacity,lt:LaunchTemplate,instancias:Instances[].{id:InstanceId,az:AvailabilityZone,estado:LifecycleState,salud:HealthStatus,lt_version:LaunchTemplate.Version}}' --output json
    aws elbv2 describe-target-health --target-group-arn "$TG" --output json
  } > "$d.json" 2>&1 &
  wait
  local g t
  g="$(tr '\t\r\n' ';  ' < "$d.g")"; t="$(tr '\t\r\n' ',  ' < "$d.t")"
  echo "$utc,$g,$t" >> "$CSV"
  echo "  $utc | grupos: $g | targets: $t"
  rm -f "$d.g" "$d.t"
}

echo "Consultando grupos del alumno a007 y destinos cada ${INTERVALO} s. Ctrl+C para detener."
inicio=$(date +%s); n=0
while true; do
  objetivo=$(( inicio + n * INTERVALO ))
  printf -v ahora '%(%s)T' -1
  resto=$(( objetivo - ahora )); [ "$resto" -gt 0 ] && sleep "$resto"
  printf -v utc '%(%Y-%m-%dT%H:%M:%S)TZ' -1
  consulta "$utc" &
  n=$((n + 1))
done
