#!/usr/bin/env bash
# Usado por el pipeline despues de `terraform apply`. El exito de apply NO
# significa que el cambio termino: este script espera el resultado real del
# controlador (Instance Refresh) y comprueba la estabilizacion.
#
# Uso: scripts/esperar_refresh.sh <ASG> <TG-ARN> <endpoint> <version_esperada> <lt_version>
# Sale con error si el refresh no termina en Successful o si algo no cuadra.

set -euo pipefail
ASG="$1"; TG="$2"; ENDPOINT="${3%/}"; VERSION="$4"; LTV="$5"
LIMITE=$((45 * 60))
t0=$(date +%s)

echo "== Esperando el resultado del Instance Refresh de $ASG =="
while true; do
  estado="$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 1 \
    --query 'InstanceRefreshes[0].Status' --output text)"
  pct="$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --max-records 1 \
    --query 'InstanceRefreshes[0].PercentageComplete' --output text)"
  echo "$(date -u +%H:%M:%SZ) estado=$estado avance=$pct%"
  case "$estado" in
    None) echo "No hay Instance Refresh (despliegue inicial o sin cambio de plantilla)."; break ;;
    Successful) echo "Instance Refresh terminado: Successful"; break ;;
    Failed|Cancelled|RollbackSuccessful|RollbackFailed)
      echo "ERROR: el Instance Refresh termino en $estado"; exit 1 ;;
  esac
  if [ $(( $(date +%s) - t0 )) -gt $LIMITE ]; then echo "ERROR: tiempo de espera agotado"; exit 1; fi
  sleep 20
done

echo "== Capacidad y version de plantilla de las instancias en servicio =="
deseada="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)"
sanas="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy' && LaunchTemplate.Version=='$LTV'])" --output text)"
ids="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text)"
echo "Deseada=$deseada | InService+Healthy con plantilla v$LTV=$sanas | Instancias: $ids"
[ "$sanas" -ge "$deseada" ] || { echo "ERROR: capacidad sana insuficiente con la plantilla vigente"; exit 1; }

echo "== Destinos del ALB =="
aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text
no_sanos="$(aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query 'length(TargetHealthDescriptions[?TargetHealth.State!=`healthy`])' --output text)"
[ "$no_sanos" -eq 0 ] || { echo "ERROR: hay destinos no sanos o drenando"; exit 1; }

echo "== Version efectiva servida por el ALB (20 muestras) =="
malas=0; vistos=""
for i in $(seq 1 20); do
  r="$(curl -sS --max-time 5 -w ' HTTP=%{http_code}' "$ENDPOINT/api/check" || echo 'ERROR HTTP=000')"
  v="$(echo "$r" | grep -o '"version": "[^"]*"' | head -1 | cut -d'"' -f4)"
  id="$(echo "$r" | grep -o '"resource_id": "[^"]*"' | head -1 | cut -d'"' -f4)"
  code="${r##*HTTP=}"
  echo "  #$i HTTP=$code version=$v recurso=$id"
  if [ "$code" != "200" ] || [ "$v" != "$VERSION" ] || ! echo "$ids" | grep -qw "$id"; then malas=$((malas + 1)); fi
  sleep 1
done
[ "$malas" -eq 0 ] || { echo "ERROR: $malas respuesta(s) no corresponden a $VERSION o a instancias en servicio"; exit 1; }
echo "OK: estabilizado en $VERSION con capacidad $deseada. Hora UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
