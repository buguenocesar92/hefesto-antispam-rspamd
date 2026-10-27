#!/usr/bin/env bats
load 'ayudante'

setup() {
  preparar_kit
  preparar_datos
}

teardown() {
  rm -rf "$BATS_TEST_TMPDIR/kit"
}

@test "el respaldo escribe manifest.json con las cinco claves del contrato" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  [ -f "$RESPALDO/manifest.json" ]
  run python3 -c "import json,sys; m=json.load(open(sys.argv[1])); falta=[k for k in ('software','version','database','sha256','status') if k not in m]; assert not falta, falta; assert m['status']=='completed', m['status']; assert m['software']=='hefesto-antispam', m['software']" "$RESPALDO/manifest.json"
  [ "$status" -eq 0 ]
}

@test "el .env no queda en claro en el respaldo" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  [ ! -f "$RESPALDO/.env" ]
  [ -f "$RESPALDO/env.vars" ]
  run grep -F "SECRETO_DE_PRUEBA" "$RESPALDO/env.vars"
  [ "$status" -eq 0 ]
  run grep -R -F "valor-ficticio-no-real" "$RESPALDO"
  [ "$status" -ne 0 ]
}

@test "con receptor age el .env viaja cifrado" {
  if ! generar_receptor_age; then skip "age-keygen no disponible en este entorno"; fi
  run construir_respaldo
  [ "$status" -eq 0 ]
  [ -f "$RESPALDO/env.age" ]
  run grep -R -F "valor-ficticio-no-real" "$RESPALDO"
  [ "$status" -ne 0 ]
}

@test "check_backup acepta el respaldo integro" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  run python3 "$KIT/scripts/check_backup.py" "$RESPALDO"
  [ "$status" -eq 0 ]
}

@test "check_backup rechaza un artefacto alterado" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  printf 'alterado\n' >> "$RESPALDO/redis/dump.rdb"
  run python3 "$KIT/scripts/check_backup.py" "$RESPALDO"
  [ "$status" -eq 2 ]
}

@test "check_backup rechaza un .env en claro dentro del respaldo" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  cp "$KIT/.env" "$RESPALDO/.env"
  run python3 "$KIT/scripts/check_backup.py" "$RESPALDO"
  [ "$status" -eq 4 ]
}

@test "check_backup rechaza un respaldo no completado" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  python3 -c "import json,sys; p=sys.argv[1]; m=json.load(open(p)); m['status']='failed'; json.dump(m, open(p,'w'))" "$RESPALDO/manifest.json"
  run python3 "$KIT/scripts/check_backup.py" "$RESPALDO"
  [ "$status" -eq 2 ]
}

@test "el script de respaldo invoca el contrato y no copia el .env en claro" {
  [ -f "$KIT/scripts/backup-rspamd.sh" ]
  run grep -c "respaldo_contrato.py env" "$KIT/scripts/backup-rspamd.sh"
  [ "$status" -eq 0 ]
  run grep -c "respaldo_contrato.py manifest" "$KIT/scripts/backup-rspamd.sh"
  [ "$status" -eq 0 ]
  run grep -cE "cp .*\.env|copy .*\.env" "$KIT/scripts/backup-rspamd.sh"
  [ "$status" -ne 0 ]
}

@test "el script de restauracion exige confirmacion explicita" {
  [ -f "$KIT/scripts/restore-rspamd.sh" ]
  run grep -c "CONFIRMAR_RESTAURACION" "$KIT/scripts/restore-rspamd.sh"
  [ "$status" -eq 0 ]
  run grep -c -- "--dry-run" "$KIT/scripts/restore-rspamd.sh"
  [ "$status" -eq 0 ]
}

@test "la restauracion deja informe y auditoria" {
  run construir_respaldo
  [ "$status" -eq 0 ]
  run python3 "$KIT/scripts/respaldo_contrato.py" report --dest "$RESPALDO" --software "hefesto-antispam" --version "4.2.2" --database "redis" --modo confirmado --resultado restaurado --destino "$KIT"
  [ "$status" -eq 0 ]
  [ -f "$RESPALDO/restore-report.json" ]
  run python3 "$KIT/scripts/respaldo_contrato.py" audit --root "$KIT" --software "hefesto-antispam" --operacion restore --origen "$RESPALDO" --destino "$KIT" --resultado restaurado
  [ "$status" -eq 0 ]
  [ -f "$KIT/logs/restore.log" ]
  run grep -F "restore" "$KIT/logs/restore.log"
  [ "$status" -eq 0 ]
}

@test "el script de restauracion verifica el respaldo contra el contrato" {
  [ -f "$KIT/scripts/restore-rspamd.sh" ]
  run grep -c "respaldo_contrato.py check" "$KIT/scripts/restore-rspamd.sh"
  [ "$status" -eq 0 ]
}
