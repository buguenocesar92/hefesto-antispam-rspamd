# ayudante: kit de pruebas aislado para este repo.
#
# Nunca toca el .env real ni Docker real: el kit se copia a un directorio
# temporal con un .env sintetico y los stubs de tests/stubs/ responden por
# Docker.
RAIZ="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RAIZ
export HEFESTO_KIT_TEST=1
export PATH="$RAIZ/tests/stubs:$PATH"

preparar_kit() {
  KIT="$BATS_TEST_TMPDIR/kit"
  rm -rf "$KIT"
  mkdir -p "$KIT/backups"
  cp -R "$RAIZ/scripts" "$KIT/scripts"
  rm -rf "$KIT/scripts/__pycache__"
  printf 'SECRETO_DE_PRUEBA=valor-ficticio-no-real\nVOLUME_PREFIX=prueba\n' > "$KIT/.env"
  chmod 600 "$KIT/.env"
  export KIT
}

preparar_datos() {
  RESPALDO="$KIT/backups/sintetico"
  rm -rf "$RESPALDO"
  mkdir -p "$RESPALDO"
  mkdir -p "$RESPALDO/datos" "$RESPALDO/redis" "$RESPALDO/config"
  printf 'clasificador sintetico\n' > "$RESPALDO/datos/bayes.txt"
  printf 'rdb sintetico\n' > "$RESPALDO/redis/dump.rdb"
  printf 'configuracion sintetica\n' > "$RESPALDO/config/local.conf"
  export RESPALDO
  export STUB_RUNNING=1
  export STUB_FIND_OUTPUT=""
  export STUB_PSQL_OUT=0
}

construir_respaldo() {
  # Reproduce el paso final del script de respaldo del kit: los nombres de
  # variable (.env fuera de claro) y el manifiesto de cinco claves.
  python3 "$KIT/scripts/respaldo_contrato.py" env --root "$KIT" --dest "$RESPALDO" >/dev/null || return 1
  python3 "$KIT/scripts/respaldo_contrato.py" manifest --dest "$RESPALDO" \
    --software "hefesto-antispam" --version "4.2.2" --database "redis" >/dev/null || return 1
}

generar_receptor_age() {
  # Genera un par de claves age efimero SOLO en el directorio temporal de la
  # prueba. Nunca se versiona ni se usa fuera de la suite.
  if ! command -v age-keygen >/dev/null 2>&1; then
    return 1
  fi
  local dir="$BATS_TEST_TMPDIR/age"
  mkdir -p "$dir"
  chmod 700 "$dir"
  if ! age-keygen -o "$dir/clave.txt" >/dev/null 2>&1; then
    return 1
  fi
  AGE_RECIPIENT="$(sed -n 's/^# public key: //p' "$dir/clave.txt")"
  export AGE_RECIPIENT
  [ -n "$AGE_RECIPIENT" ]
}
