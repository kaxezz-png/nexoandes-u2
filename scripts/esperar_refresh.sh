#!/usr/bin/env bash
# Usado por el pipeline despues de `terraform apply`. El exito de apply NO
# basta: se comprueba la estabilizacion en el proveedor.
# (El Learner Lab niega Instance Refresh; el reemplazo lo hace Terraform
# creando un ASG nuevo y destruyendo el anterior. Este script comprueba el
# resultado: un solo ASG activo, capacidad sana, destinos sanos y version.)
#
# Uso: scripts/esperar_refresh.sh <ASG> <TG-ARN> <endpoint> <version_esperada> <lt_version>

set -euo pipefail
ASG="$1"; TG="$2"; ENDPOINT="${3%/}"; VERSION="$4"; LTV="$5"

echo "== Grupos EC2 del alumno (debe quedar solo $ASG) =="
aws autoscaling describe-auto-scaling-groups --filters "Name=tag:alumno,Values=a007" \
  --query 'AutoScalingGroups[].[AutoScalingGroupName,DesiredCapacity,length(Instances)]' --output text

echo "== Esperando destinos sanos en el ALB (max 10 min) =="
for i in $(seq 1 30); do
  total="$(aws elbv2 describe-target-health --target-group-arn "$TG" --query 'length(TargetHealthDescriptions)' --output text)"
  sanos="$(aws elbv2 describe-target-health --target-group-arn "$TG" --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"
  echo "$(date -u +%H:%M:%SZ) destinos sanos=$sanos de $total"
  [ "$sanos" -ge 1 ] && [ "$sanos" -eq "$total" ] && break
  sleep 20
done
aws elbv2 describe-target-health --target-group-arn "$TG" --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output text

echo "== Capacidad y version de plantilla del grupo activo =="
deseada="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)"
sanas="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy' && LaunchTemplate.Version=='$LTV'])" --output text)"
ids="$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' --output text)"
echo "Deseada=$deseada | InService+Healthy con plantilla v$LTV=$sanas | Instancias: $ids"
[ "$sanas" -ge "$deseada" ] || { echo "ERROR: capacidad sana insuficiente"; exit 1; }
[ "$sanos" -eq "$total" ] || { echo "ERROR: hay destinos no sanos o drenando"; exit 1; }

echo "== Version efectiva servida por el ALB (20 muestras) =="
malas=0
for i in $(seq 1 20); do
  r="$(curl -sS --max-time 5 -w ' HTTP=%{http_code}' "$ENDPOINT/api/check" || echo 'ERROR HTTP=000')"
  v="$(echo "$r" | grep -o '"version": "[^"]*"' | head -1 | cut -d'"' -f4)"
  id="$(echo "$r" | grep -o '"resource_id": "[^"]*"' | head -1 | cut -d'"' -f4)"
  code="${r##*HTTP=}"
  echo "  #$i HTTP=$code version=$v recurso=$id"
  if [ "$code" != "200" ] || [ "$v" != "$VERSION" ] || ! echo "$ids" | grep -qw "$id"; then malas=$((malas + 1)); fi
  sleep 1
done
[ "$malas" -eq 0 ] || { echo "ERROR: $malas respuesta(s) no corresponden a $VERSION o al grupo activo"; exit 1; }
echo "OK: estabilizado en $VERSION con capacidad $deseada. Hora UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
