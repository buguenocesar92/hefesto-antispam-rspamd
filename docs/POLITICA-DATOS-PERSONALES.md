# Política de tratamiento de datos personales — Antispam (Rspamd) (Hefesto Studio)

Estado: vigente desde 2026-10-20. Responsable del tratamiento: el cliente que
opera el kit. Este documento describe qué datos guarda el kit, por qué, cuánto
tiempo los retiene y cómo se ejercen los derechos del titular (Ley 21.719).

## 1. Qué datos guarda este kit

El kit de antispam (Rspamd) guarda, por mensaje de correo:

- **Cabeceras y metadatos del mensaje**: remitente, destinatarios, asunto,
  IP de origen, resultado del filtro y motivo del rechazo.
- **Historial de greylist y de clasificación**: quién quedó en cuarentena,
  quién fue descartado y cuándo.
- **Claves DKIM privadas**: son la identidad criptográfica del dominio del
  cliente. Quien las tenga puede firmar correo como el cliente.
- **Estado de Redis**: clasificadores bayes, contadores de tasa y límites.
- **Copias locales de respaldo**: `backups/<timestamp>/` con el volumen de
  Rspamd, el `dump.rdb` de Redis y la configuración local.

Los metadatos de correo identifican a personas (remitente y destinatario). Las
claves DKIM no son datos personales, pero son material de autenticidad: su
pérdida obliga a republicar los registros DNS.

## 2. Qué datos NO guarda este kit

- El `.env` **no** se copia en claro al respaldo: solo sus nombres de variable
  (`env.vars`) y, si hay un receptor `age` configurado, el `.env` cifrado
  (`env.age`). Ver `docs/CONTRATO-RESPALDO.md`, regla 5.
- El `.env` nunca se copia en claro: solo sus nombres (`env.vars`) y, si hay receptor `age`, el `.env` cifrado (`env.age`).

## 3. Base legal y deberes

- **Minimización**: el kit guarda el mínimo para filtrar: metadatos del mensaje y resultado. No guarda el cuerpo del correo, ni adjuntos, ni credenciales del usuario final.
- **Finalidad**: filtrar el correo del cliente y proteger su dominio. Los datos no se usan para otros fines ni se ceden a terceros.
- **Seguridad**: los respaldos se cifran en reposo hacia el destino del
  operador, la clave privada no está en este servidor y el `.env` nunca sale
  en claro.
- **Auditoría**: cada respaldo y cada restauración dejan registro en
  `logs/restore.log` con origen, sha256 verificado, destino y resultado. Es
  registro de actividades de tratamiento: no guarda valores de secretos.

## 4. Retención

| Dato | Dónde | Retención por defecto | Quién lo borra |
|---|---|---|---|
| Metadatos de correo filtrado | Redis (volumen `redis-data`) | según la retención del cliente | el operador |
| Clasificadores bayes | volumen `rspamd-data` | mientras el kit exista | el operador |
| Claves DKIM privadas | volumen `rspamd-data` | mientras el kit exista; su pérdida obliga a republicar los registros DNS | el operador |
| Cuarentena (greylist) | volumen `rspamd-data` | según la política del cliente | el operador |
| Configuración local | `config/local.d` | mientras el kit exista | el operador |
| Respaldos en disco | `backups/<timestamp>/` | **a definir por el operador**; el kit no borra nada por su cuenta | el operador |
| Registro de auditoría | `logs/restore.log` | append-only; se trunca por política del cliente | el operador |

**El kit no borra respaldos ni datos por su cuenta.** Borrar es una decisión del
operador, porque un respaldo borrado no se recupera.

## 5. Derechos del titular (acceso, rectificación y supresión)

1. **Acceso**: entregar los datos de un titular concreto desde la interfaz del
   kit o desde el dump de la base.
2. **Rectificación**: corregir los datos desde la interfaz del kit.
3. **Supresión**: eliminar el registro y dejar constancia de la supresión en el
   registro de auditoría.
4. **Revocación del consentimiento**: si el tratamiento depende del
   consentimiento, eliminar el registro.

El kit garantiza que los datos son localizables, corregibles y borrables; el
cliente es quien conoce la identidad de los titulares.

## 6. Verificación

- `bats tests/backup_restore.bats` comprueba, con datos sintéticos, que el
  `.env` no queda en claro, que el manifiesto lleva las cinco claves, que un
  artefacto alterado se rechaza y que un destino no vacío aborta la
  restauración.
- `gitleaks` corre en CI sobre el repositorio y su historial.
