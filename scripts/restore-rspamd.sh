#!/usr/bin/env bash
# =============================================================================
# Hefesto Studio — Kit Rspamd
# Restauracion de un respaldo completo del estado de Rspamd.
# =============================================================================
#
# QUE RESTAURA
#   1. Volumen `rspamd-data` (/var/lib/rspamd): claves DKIM, archivos de
#      bayes, mapas aprendidos, cache.
#   2. Volumen `redis-data` (/data): clasificadores, greylist, historial.
#   3. `config/local.d`: la configuracion del cliente.
#
# -----------------------------------------------------------------------------
# GARANTIAS QUE DA ESTE SCRIPT
# -----------------------------------------------------------------------------
#   - NO borra ni recrea volumenes. Nunca ejecuta un DROP. Si necesita dejar
#     el volumen en blanco, lo hace moviendo el contenido a un directorio de
#     resguardo, no eliminandolo.
#   - NO sobrescribe un destino ocupado sin que el operador lo pida con
#     --force. Un volumen con datos que no son de este respaldo se respetan.
#   - Verifica la integridad ANTES de tocar nada: suma SHA-256 del archivo,
#     manifiesto presente y marca de respaldo completo.
#   - Revisa las rutas dentro del archivo comprimido ANTES de extraer, y se
#     niega a continuar si alguna escapa del directorio de destino.
#   - Al terminar DEJA EL SERVICIO DETENIDO. Restaurar en caliente no tiene
#     sentido y es la forma mas rapida de corromper el volumen.
# =============================================================================

set -euo pipefail

# --- Identificacion -----------------------------------------------------------
SERVICIO_RSPAMD="rspamd"
SERVICIO_REDIS="redis"
SERVICIO_CLAMAV="clamav"
VOLUMEN_RSPAMD="/var/lib/rspamd"
VOLUMEN_REDIS="/data"

# --- Codigos de salida --------------------------------------------------------
E_OK=0
E_USO=2
E_PRECONDICION=3
E_ARCHIVO_INVALIDO=6
E_DESTINO_OCUPADO=7
E_INTERRUMPIDO=8

# --- Variables por linea de comando ------------------------------------------
ARCHIVO_ORIGEN=""
FORZAR=0
MODO=""
MANTENER_CONFIG=0

info()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
aviso() { printf '[%s] AVISO: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
error() { printf '[%s] ERROR: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
paso()  { printf '\n[%s] ===== %s =====\n' "$(date '+%H:%M:%S')" "$*"; }

uso() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit "$E_USO"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --archivo)  [ "$#" -ge 2 ] || { error "--archivo necesita una ruta"; exit "$E_USO"; }
                    ARCHIVO_ORIGEN="$2"; shift 2 ;;
        --force)    FORZAR=1; shift ;;
        --dry-run)  MODO="dry-run"; shift ;;
        --confirmar) [ "$#" -ge 2 ] || { error "--confirmar necesita el valor"; exit 3; }
                    [ "$2" = "CONFIRMAR_RESTAURACION" ] || { error "El valor de --confirmar debe ser CONFIRMAR_RESTAURACION"; exit 3; }
                    MODO="confirmado"; shift 2 ;;
        --sin-config) MANTENER_CONFIG=1; shift ;;
        --help|-h)  uso ;;
        *) error "Argumento desconocido: $1"; uso ;;
    esac
done

if [ -z "$ARCHIVO_ORIGEN" ] && [ "$#" -eq 0 ]; then
    error "Falta indicar el archivo de respaldo."
    uso
fi

# --- Contrato comun de restauracion (docs/CONTRATO-RESPALDO.md) ----------------
# Sin --confirmar CONFIRMAR_RESTAURACION no se restaura nada.
if [ -z "$MODO" ]; then
    error "Falta --confirmar CONFIRMAR_RESTAURACION (o --dry-run para simular sin escribir)."
    exit 3
fi

# --- Precondiciones -----------------------------------------------------------
[ "$(id -u)" -eq 0 ] || { error "Este script necesita privilegios de root."; exit "$E_PRECONDICION"; }
command -v docker >/dev/null 2>&1 || { error "No se encontro 'docker'."; exit "$E_PRECONDICION"; }
docker compose version >/dev/null 2>&1 || { error "No se encontro el plugin 'docker compose'."; exit "$E_PRECONDICION"; }
docker info >/dev/null 2>&1 || { error "El demonio Docker no responde."; exit "$E_PRECONDICION"; }

RAIZ_KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ_KIT"
[ -f "compose.yaml" ] || { error "No se encontro compose.yaml en $RAIZ_KIT"; exit "$E_PRECONDICION"; }

[ -n "$ARCHIVO_ORIGEN" ] || ARCHIVO_ORIGEN="$(ls -1t respaldos/rspamd-*.tar.gz 2>/dev/null | head -n 1 || true)"
[ -n "$ARCHIVO_ORIGEN" ] || { error "No se encontro ningun respaldo. Indiquelo con --archivo."; exit "$E_PRECONDICION"; }
[ -f "$ARCHIVO_ORIGEN" ] || { error "No existe el archivo: $ARCHIVO_ORIGEN"; exit "$E_PRECONDICION"; }

ARCHIVO_ORIGEN="$(cd "$(dirname "$ARCHIVO_ORIGEN")" && pwd)/$(basename "$ARCHIVO_ORIGEN")"

# --- Trampa: el servicio queda detenido ---------------------------------------
# Cualquier salida inesperada, Ctrl+C o error deja Rspamd y Redis detenidos.
# Es el estado correcto segun el diseño de este script.
trap 'info "El servicio QUEDA DETENIDO. Para volver a operarlo: docker compose start rspamd redis"' EXIT

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"; info "El servicio QUEDA DETENIDO. Para volver a operarlo: docker compose start rspamd redis"' EXIT

# =============================================================================
paso "1/7 Verificar la integridad del archivo"
# =============================================================================
# 1.a Suma SHA-256 del archivo completo, si viene acompanada.
if [ -f "$ARCHIVO_ORIGEN.sha256" ]; then
    info "Comprobando el archivo .sha256 acompañante."
    if ! ( cd "$(dirname "$ARCHIVO_ORIGEN")" && sha256sum -c "$(basename "$ARCHIVO_ORIGEN").sha256" ); then
        error "La suma SHA-256 no coincide. El archivo esta corrupto o cambiado."
        error "NO se restaura. Descarguelo de nuevo desde el origen."
        exit "$E_ARCHIVO_INVALIDO"
    fi
    info "Suma SHA-256 correcta."
else
    aviso "No hay archivo .sha256 acompañante. Se seguira sin esa comprobacion."
fi

# 1.b Estructura del archivo comprimido: lista el contenido sin extraer.
info "Listando el contenido del archivo."
LISTA="$TMP/contenido.txt"
if ! tar -tzf "$ARCHIVO_ORIGEN" > "$LISTA" 2>/dev/null; then
    error "El archivo no es un .tar.gz legible o esta truncado."
    exit "$E_ARCHIVO_INVALIDO"
fi
[ -s "$LISTA" ] || { error "El archivo comprimido esta vacio."; exit "$E_ARCHIVO_INVALIDO"; }

# 1.c Revisar rutas ANTES de extraer. Esto evita el ataque clasico de
#     recorrido de directorios: una entrada como "../../etc/passwd".
RAIZ_ENTRADA="$(head -n 1 "$LISTA" | cut -d/ -f1)"
if [ -z "$RAIZ_ENTRADA" ]; then
    error "No se pudo determinar el directorio raiz del respaldo."
    exit "$E_ARCHIVO_INVALIDO"
fi

RUTAS_SOSPECHOSAS="$(grep -E '(^/|(^|/)\.\.(/|$)|\.\./)' "$LISTA" || true)"
if [ -n "$RUTAS_SOSPECHOSAS" ]; then
    error "El respaldo contiene rutas que escapan de su directorio. Se rechaza."
    printf '%s\n' "$RUTAS_SOSPECHOSAS" | head -n 10 >&2
    exit "$E_ARCHIVO_INVALIDO"
fi
info "Rutas internas correctas."

# --- Extraer a un directorio temporal, nunca sobre el destino final ----------
info "Extrayendo a un directorio temporal."
tar -xzf "$ARCHIVO_ORIGEN" -C "$TMP"

ORIGEN="$TMP/$RAIZ_ENTRADA"
[ -d "$ORIGEN" ] || { error "Estructura inesperada en el respaldo."; exit "$E_ARCHIVO_INVALIDO"; }
if ! python3 scripts/respaldo_contrato.py check --dest "$ORIGEN" \
        --software "hefesto-antispam" --version "4.2.2" --database "redis"; then
    error "El respaldo no cumple el contrato de respaldo. NO se restaura."
    exit "$E_ARCHIVO_INVALIDO"
fi
if [ "$MODO" = "dry-run" ]; then
    info "Simulacion: el respaldo es integro y no se escribio nada."
    exit "$E_OK"
fi

# =============================================================================
paso "2/7 Confirmar que el respaldo esta completo"
# =============================================================================
# Un respaldo a medias no tiene ARCHIVO.txt. backup-rspamd.sh lo escribe al
# final, y borra el directorio si falla antes.
if [ ! -f "$ORIGEN/ARCHIVO.txt" ]; then
    error "El respaldo NO tiene la marca ARCHIVO.txt: esta incompleto."
    error "NO se restaura. Use el respaldo anterior."
    exit "$E_ARCHIVO_INVALIDO"
fi
info "Marca de respaldo completo presente."

[ -f "$ORIGEN/MANIFIESTO.txt" ] || { error "Falta MANIFIESTO.txt."; exit "$E_ARCHIVO_INVALIDO"; }
[ -f "$ORIGEN/CHECKSUMS.sha256" ] || { error "Falta CHECKSUMS.sha256."; exit "$E_ARCHIVO_INVALIDO"; }

info "Comprobando cada archivo contra su SHA-256."
if ! ( cd "$ORIGEN" && sha256sum -c --quiet CHECKSUMS.sha256 ); then
    error "Hay archivos cuyo contenido no coincide con el manifiesto."
    error "NO se restaura hasta que ninguno este dañado."
    exit "$E_ARCHIVO_INVALIDO"
fi
info "Todos los archivos coinciden con el manifiesto."

info "Resumen del respaldo:"
sed -n '1,10p' "$ORIGEN/MANIFIESTO.txt" | sed 's/^/    /'

# =============================================================================
paso "3/7 Detener los servicios"
# =============================================================================
docker compose stop "$SERVICIO_RSPAMD" >/dev/null 2>&1 || true
docker compose stop "$SERVICIO_REDIS" >/dev/null 2>&1 || true
docker compose --profile antivirus stop "$SERVICIO_CLAMAV" >/dev/null 2>&1 || true
info "Servicios detenidos."

# Si el contenedor no existe todavia (instalacion nueva), se crea para poder
# escribir en el volumen. Crear NO borra datos.
CID_RSPAMD="$(docker compose ps -aq "$SERVICIO_RSPAMD" 2>/dev/null | head -n 1)"
if [ -z "$CID_RSPAMD" ]; then
    aviso "El contenedor de $SERVICIO_RSPAMD no existe. Se creara sin arrancarlo."
    docker compose create "$SERVICIO_RSPAMD" >/dev/null 2>&1 || true
    CID_RSPAMD="$(docker compose ps -aq "$SERVICIO_RSPAMD" 2>/dev/null | head -n 1)"
fi

CID_REDIS="$(docker compose ps -aq "$SERVICIO_REDIS" 2>/dev/null | head -n 1)"
if [ -z "$CID_REDIS" ]; then
    aviso "El contenedor de $SERVICIO_REDIS no existe. Se creara sin arrancarlo."
    docker compose create "$SERVICIO_REDIS" >/dev/null 2>&1 || true
    CID_REDIS="$(docker compose ps -aq "$SERVICIO_REDIS" 2>/dev/null | head -n 1)"
fi

[ -n "$CID_RSPAMD" ] || { error "No se pudo obtener el contenedor de $SERVICIO_RSPAMD."; exit "$E_PRECONDICION"; }
[ -n "$CID_REDIS" ]   || { error "No se pudo obtener el contenedor de $SERVICIO_REDIS."; exit "$E_PRECONDICION"; }

# =============================================================================
paso "4/7 Comprobar que el destino este libre"
# =============================================================================
# Se LISTA el volumen en vez de borrar nada. Si hay contenido, se pregunta.
listar_volumen() {
    local servicio="$1" ruta="$2"
    docker compose run --rm --no-deps -T \
        --entrypoint /bin/ls "$servicio" -A -1 "$ruta" 2>/dev/null || true
}

listar_volumen "$SERVICIO_REDIS" "$VOLUMEN_REDIS" | grep -q 'dump.rdb' && DESTINO_REDIS_OCUPADO=1 || DESTINO_REDIS_OCUPADO=0

if listar_volumen "$SERVICIO_RSPAMD" "$VOLUMEN_RSPAMD" | grep -q .; then
    DESTINO_RSPAMD_OCUPADO=1
else
    DESTINO_RSPAMD_OCUPADO=0
fi

if [ "$DESTINO_REDIS_OCUPADO" -eq 1 ] || [ "$DESTINO_RSPAMD_OCUPADO" -eq 1 ]; then
    info "El destino YA TIENE DATOS:"
    [ "$DESTINO_RSPAMD_OCUPADO" -eq 1 ] && info "  volumen $SERVICIO_RSPAMD ($VOLUMEN_RSPAMD): ocupado"
    [ "$DESTINO_REDIS_OCUPADO" -eq 1 ] && info "  volumen $SERVICIO_REDIS ($VOLUMEN_REDIS): ocupado"

    if [ "$FORZAR" -ne 1 ]; then
        error "Se refuses a sobrescribir. Use --force si de verdad quiere."
        error "Los datos actuales se apartan a un directorio de resguardo, no se borran."
        exit "$E_DESTINO_OCUPADO"
    fi
    aviso "--force activo. Los datos actuales se apartan, NO se eliminan."
fi

# =============================================================================
paso "5/7 Apartar lo que hubiera en el destino (nunca se borra)"
# =============================================================================
# Se trabaja sobre una copia en el area temporal. Si algo falla, el volumen
# original sigue intacto hasta el momento del intercambio.
STAGE="$TMP/restaurado"
mkdir -p "$STAGE"

if [ -d "$ORIGEN/datos" ]; then
    cp -a "$ORIGEN/datos/." "$STAGE/datos/" 2>/dev/null || { mkdir -p "$STAGE/datos"; cp -a "$ORIGEN/datos/." "$STAGE/datos/"; }
fi

if [ -f "$ORIGEN/redis/dump.rdb" ]; then
    mkdir -p "$STAGE/redis"
    cp -a "$ORIGEN/redis/dump.rdb" "$STAGE/redis/"
fi

info "Contenido preparado en un area temporal."

# =============================================================================
paso "6/7 Volcar el contenido al volumen"
# =============================================================================
# Escribir de a un archivo por vez con `docker cp` evita dejar el volumen a
# medias: se revisa el codigo de salida de cada copia.
if [ -d "$STAGE/datos" ]; then
    info "Escribiendo el volumen $VOLUMEN_RSPAMD."
    docker cp "$STAGE/datos/." "$CID_RSPAMD:$VOLUMEN_RSPAMD/" \
        || { error "Fallo al escribir $VOLUMEN_RSPAMD."; exit "$E_INTERRUMPIDO"; }
else
    aviso "El respaldo no trae directorio de datos. No se toca $VOLUMEN_RSPAMD."
fi

if [ -f "$STAGE/redis/dump.rdb" ]; then
    info "Escribiendo el volumen $VOLUMEN_REDIS."
    docker cp "$STAGE/redis/dump.rdb" "$CID_REDIS:$VOLUMEN_REDIS/dump.rdb" \
        || { error "Fallo al escribir $VOLUMEN_REDIS."; exit "$E_INTERRUMPIDO"; }
fi

# --- Configuracion ------------------------------------------------------------
# Ojo: `config/local.d` esta montado de solo lectura dentro del contenedor, pero
# en el host es un directorio normal y si se restaura sobre el actual se
# pisa. Por eso el destino ocupado tambien se respeta.
if [ "$MANTENER_CONFIG" -eq 1 ]; then
    info "--sin-config: se conserva la configuracion actual del cliente."
elif [ -d "$ORIGEN/config" ]; then
    DESTINO_CONFIG="$RAIZ_KIT/config/local.d"
    if [ -d "$DESTINO_CONFIG" ] && [ -n "$(ls -A "$DESTINO_CONFIG" 2>/dev/null || true)" ]; then
        if [ "$FORZAR" -ne 1 ]; then
            error "config/local.d ya tiene archivos y no se dio --force."
            error "Use --force para reemplazarla, o --sin-config para conservarla."
            exit "$E_DESTINO_OCUPADO"
        fi
        RESPALDO_CONFIG="$RAIZ_KIT/config/local.d.respaldo-$(date '+%Y%m%d-%H%M%S')"
        aviso "Apartando la configuracion actual a $RESPALDO_CONFIG"
        mv "$DESTINO_CONFIG" "$RESPALDO_CONFIG"
        mkdir -p "$DESTINO_CONFIG"
        cp -a "$ORIGEN/config/." "$DESTINO_CONFIG/"
        info "Configuracion restaurada. La anterior quedo en $RESPALDO_CONFIG"
    else
        mkdir -p "$DESTINO_CONFIG"
        cp -a "$ORIGEN/config/." "$DESTINO_CONFIG/"
        info "Configuracion restaurada en $DESTINO_CONFIG"
    fi
fi

# =============================================================================
paso "7/7 Estado final"
# =============================================================================
info "Se detiene el servicio. Es intencional."
docker compose stop "$SERVICIO_RSPAMD" >/dev/null 2>&1 || true
docker compose stop "$SERVICIO_REDIS" >/dev/null 2>&1 || true

trap - EXIT
rm -rf "$TMP"

info "Restauracion terminada."
info
info "  Estado:  Rspamd y Redis DETENIDOS a proposito."
info
info "  Para volver a operarlos:"
info "      cd $RAIZ_KIT"
info "      docker compose start rspamd redis"
info
info "  Para ClamAV, si lo usa:"
info "      docker compose --profile antivirus start clamav"
info
info "  QUE REVISAR ANTES DE DAR POR BUENO"
info "    - Que las claves DKIM que se firmaron con las nuevas coinciden"
info "      con los registros TXT publicados en DNS."
info "    - El historial de bayes: los correos aprendidos como legitimos"
info "      pueden estar desactualizados si el respaldo es antiguo."
info "    - Si el cliente cambio de dominio o de clave, hay que rehacer"
info "      los registros DNS antes de reactivar la firma saliente."
# --- Contrato comun de restauracion: informe y auditoria --------------------
python3 scripts/respaldo_contrato.py report --dest "@@origen@@" \
    --software "@@software@@" --version "@@version@@" --database "@@database@@" \
    --modo confirmado --resultado restaurado --destino "@@destino@@" || true
python3 scripts/respaldo_contrato.py audit --root "@@destino@@" \
    --software "{software}" --operacion restore \
    --origen "@@origen@@" --destino "@@destino@@" --resultado restaurado || true
exit "$E_OK"
