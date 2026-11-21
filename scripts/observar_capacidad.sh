#!/usr/bin/env bash
# Observador de capacidad y controlador (protocolo U2): cada 20 s (maximo exigido: 30 s).
# Registra ASG (capacidad, instancias, salud, version de Launch Template),
# el ultimo Instance Refresh y la salud de los destinos del ALB.
#
# Uso:
#   scripts/observar_capacidad.sh <nombre-ASG> <ARN-target-group> [prefijo-archivo]
# Genera:
#   <prefijo>.csv  -> una linea resumen por consulta
#   <prefijo>.log  -> detalle JSON de cada consulta
# Requiere AWS CLI con las credenciales del laboratorio. Ctrl+C para detener.

set -u

ASG="${1:?Uso: $0 <ASG> <TG-ARN> [prefijo]}"
TG="${2:?Falta el ARN del target group}"
PREFIJO="${3:-evidencias/capacidad_$(date -u +%Y%m%dT%H%M%SZ)}"
INTERVALO=20

mkdir -p "$(dirname "$PREFIJO")"
CSV="$PREFIJO.csv"
LOG="$PREFIJO.log"
echo "utc,deseada,min,max,inservice_healthy,lt_versiones,refresh_id,refresh_estado,refresh_pct,targets_healthy,targets_total,targets" > "$CSV"

trap 'echo; echo "Registro en $CSV y $LOG"; exit 0' INT TERM
echo "Consultando $ASG cada ${INTERVALO} s. Ctrl+C para detener."

while true; do
  t0="$(date +%s)"
  utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  asg="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize,length(Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`]),join(`;`, Instances[].join(`:`, [InstanceId, LifecycleState, HealthStatus, LaunchTemplate.Version]))]' \
    --output text 2>&1 | tr '\t' ',')"
  ir="$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 1 \
    --query 'InstanceRefreshes[0].[InstanceRefreshId,Status,PercentageComplete]' --output text 2>&1 | tr '\t' ',')"
  tg="$(aws elbv2 describe-target-health --target-group-arn "$TG" \
    --query '[length(TargetHealthDescriptions[?TargetHealth.State==`healthy`]),length(TargetHealthDescriptions),join(`;`, TargetHealthDescriptions[].join(`:`, [Target.Id, TargetHealth.State]))]' \
    --output text 2>&1 | tr '\t' ',')"

  echo "$utc,$asg,$ir,$tg" >> "$CSV"
  {
    echo "=== $utc ==="
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
      --query 'AutoScalingGroups[0].{deseada:DesiredCapacity,min:MinSize,max:MaxSize,lt:LaunchTemplate,instancias:Instances[].{id:InstanceId,az:AvailabilityZone,estado:LifecycleState,salud:HealthStatus,lt_version:LaunchTemplate.Version}}' --output json
    aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 1 --output json
    aws elbv2 describe-target-health --target-group-arn "$TG" --output json
  } >> "$LOG" 2>&1

  echo "  $utc | ASG: $asg | refresh: $ir | targets: $tg"
  resto=$(( INTERVALO - ($(date +%s) - t0) ))
  [ "$resto" -gt 0 ] && sleep "$resto"
done
