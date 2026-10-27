#!/usr/bin/env bash
# Salud del kit hefesto-antispam. Solo lee: no modifica nada, no arranca nada y no
# publica ningun puerto. Salida: 0 si todo esta bien, 1 si algo falla.
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ" || exit 1

SERVICIOS=(rspamd redis)

fallos=0
ok() { printf '[OK]    %s\n' "$1"; }
mal() { printf '[FALLA] %s\n' "$1" >&2; fallos=$((fallos + 1)); }

if docker compose  config --quiet >/dev/null 2>&1; then
  ok "el compose renderiza"
else
  mal "el compose no renderiza"
fi

for servicio in "${SERVICIOS[@]}"; do
  if docker compose  ps --status running --services 2>/dev/null | grep -qx "$servicio"; then
    ok "servicio $servicio arriba"
  else
    mal "servicio $servicio no esta arriba"
  fi
done

ULTIMO="$(ls -1d backups/*/ 2>/dev/null | tail -1)"
if [ -n "$ULTIMO" ] && [ -f "$ULTIMO/manifest.json" ]; then
  ok "existe un respaldo: $ULTIMO"
  if python3 -c "import json,sys; m=json.load(open(sys.argv[1])); sys.exit(0 if m.get('status')=='completed' else 1)" "$ULTIMO/manifest.json"; then
    ok "el ultimo respaldo esta completado"
  else
    mal "el ultimo respaldo no esta completado"
  fi
else
  mal "no hay ningun respaldo completado en backups/"
fi

if [ "$fallos" -eq 0 ]; then
  printf 'Salud del kit: OK\n'
  exit 0
fi
printf 'Salud del kit: %s comprobacion(es) fallida(s)\n' "$fallos" >&2
exit 1
