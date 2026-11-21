#!/usr/bin/env bash
# Observador HTTP del protocolo U2.
# - Una peticion GET a /api/check cada 2 s (programada contra el reloj, sin deriva).
# - Timeout de 5 s y SIN reintentos: cada peticion es una muestra independiente.
# - Cada peticion corre en segundo plano, asi una respuesta lenta no atrasa la siguiente.
# - Registra hora UTC de envio, codigo HTTP, version, identidad y recurso que respondio.
#
# Uso (Git Bash, WSL o CloudShell):
#   scripts/observar_http.sh http://<DNS-del-ALB> [evidencias/archivo.csv]
# Detener con Ctrl+C. El archivo queda completo, con todos los fallos.

set -u

ENDPOINT="${1:?Uso: $0 http://<endpoint> [archivo.csv]}"
ENDPOINT="${ENDPOINT%/}"
OUT="${2:-evidencias/http_$(date -u +%Y%m%dT%H%M%SZ).csv}"
INTERVALO=2
TIMEOUT=5

mkdir -p "$(dirname "$OUT")"
echo "seq,enviado_utc,enviado_epoch,http,duracion_s,curl_rc,version,perfil,passed,alumno,curso,x,proveedor,build_ref,resource_id,private_ip,location,metadata_ok,observed_at_utc" > "$OUT"

campo_txt() { # extrae "clave": "valor" del JSON de una linea
  grep -o "\"$1\": \"[^\"]*\"" "$2" 2>/dev/null | head -1 | cut -d'"' -f4
}
campo_raw() { # extrae "clave": valor (numeros, true/false)
  grep -o "\"$1\": [^,}]*" "$2" 2>/dev/null | head -1 | sed 's/^[^:]*: *//'
}

muestra() {
  local seq="$1" enviado_utc="$2" enviado_epoch="$3"
  local body salida rc code dur
  body="$(mktemp)"
  salida="$(curl -sS --max-time "$TIMEOUT" -o "$body" -w '%{http_code} %{time_total}' "$ENDPOINT/api/check" 2>/dev/null)"
  rc=$?
  code="${salida%% *}"; dur="${salida##* }"
  [ -z "$code" ] && code="000"
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$seq" "$enviado_utc" "$enviado_epoch" "$code" "$dur" "$rc" \
    "$(campo_txt version "$body")" "$(campo_txt profile "$body")" "$(campo_raw passed "$body")" \
    "$(campo_txt student "$body")" "$(campo_txt course "$body")" "$(campo_raw x "$body")" \
    "$(campo_txt provider "$body")" "$(campo_txt build_ref "$body")" \
    "$(campo_txt resource_id "$body")" "$(campo_txt private_ip "$body")" "$(campo_txt location "$body")" \
    "$(campo_raw metadata_ok "$body")" "$(campo_txt observed_at_utc "$body")" >> "$OUT"
  rm -f "$body"
}

terminar() {
  echo
  echo "Deteniendo: esperando las peticiones en curso (max ${TIMEOUT} s)..."
  wait
  echo "Registro completo en: $OUT ($(($(wc -l < "$OUT") - 1)) muestras)"
  exit 0
}
trap terminar INT TERM

echo "Observando $ENDPOINT/api/check cada ${INTERVALO} s (timeout ${TIMEOUT} s). Registro: $OUT"
echo "Inicio del registro (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ). Ctrl+C para detener."

inicio="$(date +%s.%N)"
seq=0
while true; do
  objetivo="$(awk -v i="$inicio" -v n="$seq" -v p="$INTERVALO" 'BEGIN{printf "%.3f", i + n*p}')"
  espera="$(awk -v o="$objetivo" -v a="$(date +%s.%N)" 'BEGIN{d=o-a; if(d<0)d=0; printf "%.3f", d}')"
  sleep "$espera"
  muestra "$seq" "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$(date +%s.%3N)" &
  if [ $((seq % 15)) -eq 0 ]; then
    echo "  $(date -u +%H:%M:%SZ) muestra #$seq enviada"
  fi
  seq=$((seq + 1))
done
