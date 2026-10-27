# Contrato de respaldo y restauración de Hefesto Studio

Este documento es **normativo**. Los kits que no lo cumplan quedan fuera del
flujo orquestado: el mismo documento está en `hefesto-monitor-uptime-kuma`
(el que produce el respaldo) y en `hefesto-respaldo-kopia` (el que lo almacena),
para que ambos extremos hablen el mismo idioma.

## 1. Las reglas

1. **Nombre del script de respaldo**: `scripts/backup.py` (Python) o
   `scripts/respaldar.sh` (Bash). Los dos extremos se reconocen por el
   contenido del respaldo, no por el nombre.
2. **Salida en `<timestamp>/`** con, como mínimo:
   - `data.tar.gz`: el contenido a respaldar.
   - `SHA256SUMS`: el sha256 de `data.tar.gz`, en formato `sha256sum`.
   - `manifest.json`: la metadata del respaldo.
3. **`manifest.json` contiene SIEMPRE** estas claves: `software`, `version`,
   `database`, `sha256`, `status`. Un respaldo sin las cinco no es un respaldo
   del flujo orquestado.
4. **`status` solo vale `completed`** si el proceso terminó sin error. Cualquier
   otro valor significa que el respaldo **no se restaura**: la restauración
   aborta antes de tocar el destino.
5. **El `.env` NUNCA se copia en claro.** Se documenta su ausencia en el
   manifiesto o se cifra con `age` usando la clave pública del receptor. Un
   `.env` en claro dentro de un respaldo es una credencial tendida en el disco
   donde aterriza el respaldo.
6. **Existe un script de restauración** que valida, en este orden: el
   `manifest.json` (versión y `status`), el checksum, las rutas dentro del tar
   (nada absoluto, nada con `..`, nada que no sea archivo o directorio) y que el
   **volumen destino esté vacío**. Nunca vacía ni sobrescribe datos existentes.
7. **Existe una prueba bats** que ejercita el ciclo completo con **datos
   sintéticos** y en aislamiento: ningún contenedor real, ningún volumen real.
   La prueba debe cubrir, como mínimo: el respaldo con su manifiesto, el `.env`
   que no queda en claro, el rechazo de un manifiesto inválido y el rechazo de
   un destino no vacío.
8. **Existe un `.env.example` sin secretos** que documenta todas las variables
   que el compose exige. Sin el, un tercero no sabe qué escribir.
9. **`gitleaks` corre en CI** sobre el repositorio y sobre el historial.
10. **El compose fija la imagen por digest**, no por etiqueta: una etiqueta
    puede cambiar de contenido sin que nadie lo note.
11. **El estado de despliegue no viaja en el repositorio**: los identificadores
    (uuid de la app, url pública, fechas) viven en un archivo de estado con
    permisos restrictivos, fuera del control de versiones.
12. **Cada restauración deja rastro de auditoría**: origen, sha256 verificado,
    destino y resultado, en un log append-only. Sin valores de secretos: solo
    nombres y hashes.

## 2. Por qué el `.env` no se copia en claro

El `.env` es lo que se lleva el acceso a la base de datos, al SMTP y a las
claves de servicio. Un respaldo vive en el disco, se copia a otro equipo, se
sube a un bucket y a veces termina en un ticket de soporte. Si el `.env` viaja
en claro, cada copia del respaldo es una copia de las credenciales.

Lo que sí puede viajar, y así viaja:

- **Los nombres de las variables** (`env.vars`): sin valores, para saber qué
  hay que rellenar en el destino.
- **El `.env` cifrado** (`env.age`), si hay un receptor age configurado.

Si no hay receptor age, el respaldo sale **sin** el `.env` y el manifiesto lo
dice. No hay modo degradado a texto plano.

## 3. El receptor `age`: quién custodia la clave

La clave pública del receptor es un **insumo externo**. La privada vive en el
gestor de secretos del cliente (Infisical, Vaultwarden) o, si el cliente no
tiene, en un sobre cifrado fuera del servidor. El kit que respalda solo usa
la pública.

Consecuencias que hay que aceptar antes de cifrar:

- **Perder la clave privada implica regenerar los secretos y volver a
  desplegar.** Los despliegues anteriores quedan inservibles.
- **Rotar la clave obliga a volver a cifrar**: los respaldos viejos siguen
  ligados a la clave con que se hicieron.

## 4. Migrar respaldos que ya existen

Los respaldos hechos antes de este contrato **no se tocan**. La migración es
manual, archivo por archivo, y nunca borra el original:

1. Cifrar con la clave del receptor **al lado** del original (`<archivo>.enc`).
2. Verificar que el descifrado devuelve el original byte a byte.
3. Recién entonces, borrar el original a mano.

Un respaldo viejo sin cifrar es un riesgo asumido y conocido: está en el punto
6 del contrato como deuda.

## 5. Cómo se verifica el contrato

```bash
bats tests/                 # la suite del kit que respalda
bats tests/backup_restore.bats   # el ciclo con datos sintéticos
```

Y del lado del que almacena:

```bash
bats tests/restaurar.bats        # el ciclo de restauración
```

Un kit que no tiene ninguna de las dos pruebas no se considera productionizado.

## 6. Cómo se propaga a los demás kits

Todo kit que publique datos a un repositorio debe:

1. Producir un respaldo con el formato de la regla 2.
2. Escribir el manifiesto de la regla 3.
3. Dejar el `.env` fuera (regla 5).
4. Poder restaurarlo con un script que aplique las reglas 6 y 12.
5. Tener una prueba con datos sintéticos (regla 7).

Los kits que no cumplen quedan fuera del flujo orquestado: su respaldo no se
puede restaurar con la misma confianza que el de los demás, y una confianza
distinta por kit es una confianza que no sirve.
