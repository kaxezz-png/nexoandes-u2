#!/usr/bin/env bash
# Analiza un registro de observar_http.sh contra la ventana del protocolo U2.
# Es un APOYO: sus resultados se contrastan con las consultas al proveedor
# (observar_capacidad.sh) y con el estado final del controlador.
#
# Uso:
#   scripts/analizar_ventana.sh <archivo.csv> <inicio_utc> <estabilizacion_utc> <version_objetivo> <versiones_en_transicion> <alumno> <curso>
# Ejemplo (v1 -> v2):
#   scripts/analizar_ventana.sh evidencias/http_X.csv 2026-11-25T01:10:00Z 2026-11-25T01:18:30Z v2 v1,v2 a007 c50
#
# Ventana evaluada: [inicio - 60 s, estabilizacion + 120 s].
# Fallo funcional: timeout/error, HTTP != 200, passed != true, identidad
# incorrecta, version fuera de las admitidas (o distinta de la objetivo
# despues de estabilizar). Brecha maxima admitida entre muestras: 7 s.

set -u
CSV="${1:?Falta el CSV}"; INICIO="${2:?Falta inicio UTC}"; ESTAB="${3:?Falta estabilizacion UTC}"
OBJ="${4:?Falta version objetivo}"; TRANS="${5:?Faltan versiones en transicion}"
ALUMNO="${6:?Falta alumno}"; CURSO="${7:?Falta curso}"

ini=$(date -u -d "$INICIO" +%s) || exit 1
est=$(date -u -d "$ESTAB" +%s) || exit 1
[ "$est" -ge "$ini" ] || { echo "ERROR: la estabilizacion no puede ser anterior al inicio"; exit 1; }
ws=$((ini - 60)); we=$((est + 120))

echo "Archivo:            $CSV"
echo "Inicio del cambio:  $INICIO"
echo "Estabilizacion:     $ESTAB"
echo "Ventana evaluada:   $(date -u -d @$ws +%Y-%m-%dT%H:%M:%SZ) -> $(date -u -d @$we +%Y-%m-%dT%H:%M:%SZ) ($((we - ws)) s)"
echo

tail -n +2 "$CSV" | sort -t, -k3,3n | awk -F, -v ws="$ws" -v we="$we" -v est="$est" \
  -v obj="$OBJ" -v trans="$TRANS" -v alumno="$ALUMNO" -v curso="$CURSO" '
BEGIN { n=0; fallos=0; maxgap=0; prev=""; split(trans, tv, ","); for (i in tv) okv[tv[i]]=1 }
{
  t=$3+0
  if (t < ws || t > we) { fuera++; next }
  n++
  if (n==1) first=t
  if (prev!="") { g=t-prev; if (g>maxgap) { maxgap=g; gapat=$2 } }
  prev=t; last=t
  motivo=""
  if ($4!="200") motivo="HTTP " $4 (($6!="0") ? " (curl rc " $6 ")" : "")
  else if ($9!="true") motivo="passed=" $9
  else if ($10!=alumno || $11!=curso || $13!="aws") motivo="identidad " $10 "/" $11 "/" $13
  else if (t>est && $7!=obj) motivo="version " $7 " despues de estabilizar"
  else if (!($7 in okv)) motivo="version " $7 " no admitida"
  if (motivo!="") { fallos++; if (fallos<=20) print "  FALLO #" $1 " " $2 " -> " motivo }
  ver[($7=="") ? "(sin_respuesta)" : $7]++
  if ($15!="") rid[$15]=$7
}
END {
  print ""
  print "Muestras en la ventana:     " n "   (fuera de la ventana, conservadas aparte: " fuera+0 ")"
  if (n==0) { print "RESULTADO: sin muestras en la ventana -> evidencia incompleta"; exit 2 }
  printf "Brecha inicial:             %.1f s (desde el inicio de la ventana)\n", first-ws
  printf "Brecha final:               %.1f s (hasta el fin de la ventana)\n", we-last
  printf "Brecha maxima entre muestras: %.1f s (en %s)\n", maxgap, gapat
  printf "Cadencia media real:        %.2f s\n", (n>1) ? (last-first)/(n-1) : 0
  print  "Fallos funcionales:         " fallos
  printf "Versiones observadas:      "; for (v in ver) printf " %s=%d", v, ver[v]; print ""
  print  "Recursos que respondieron:"
  for (r in rid) print "   " r " (" rid[r] ")"
  cobertura = (first-ws<=7 && we-last<=7 && maxgap<=7)
  print ""
  if (!cobertura) print "RESULTADO: ventana INCOMPLETA (brecha > 7 s). No cumple la aceptacion."
  else if (fallos>0) print "RESULTADO: ventana completa con " fallos " fallo(s). No cumple la aceptacion."
  else print "RESULTADO: ventana completa y cero fallos funcionales. Contrastar con capacidad y controlador."
}'
