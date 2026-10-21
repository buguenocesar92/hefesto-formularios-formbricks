#!/usr/bin/env bats
# Regresion del compose de Formbricks.
#
# El defecto original era la extension de Coolify `exclude_from_hc: true`,
# que NO existe en la Compose Specification:
# `docker compose config` rechazaba el fichero entero y el kit no se podia
# validar, ni desplegar, ni comprobar en CI.
#
# Estos tests no levantan contenedores: solo validan el modelo del compose.

@test "el compose es valido para la Compose Specification" {
  run docker compose --env-file .env.example -f compose.yaml config -q
  [ "$status" -eq 0 ] || {
    echo "docker compose config fallo:" >&2
    echo "${output}" >&2
    return 1
  }
}

@test "no queda la extension incompatible exclude_from_hc" {
  run grep -nE "^[[:space:]]*exclude_from_hc:" compose.yaml
  [ "$status" -eq 1 ] || {
    echo "exclude_from_hc sigue presente como clave en compose.yaml:" >&2
    echo "${output}" >&2
    return 1
  }
}

@test "el compose no declara un name fijo en la raiz" {
  run grep -n "^name:" compose.yaml
  [ "$status" -eq 1 ] || {
    echo "un name: fijo en la raiz entra en conflicto con Coolify:" >&2
    echo "${output}" >&2
    return 1
  }
}

@test "los servicios de un solo uso se consumen con service_completed_successfully" {
  run python3 - <<'PY'
import json
import subprocess
import sys

proc = subprocess.run(
    ["docker", "compose", "--env-file", ".env.example", "-f", "compose.yaml",
     "config", "--format", "json"],
    capture_output=True,
    text=True,
)
if proc.returncode != 0:
    print(proc.stderr.strip(), file=sys.stderr)
    sys.exit(1)

servicios = json.loads(proc.stdout).get("services", {})
esperados = {
    "authzed-db-bootstrap", "spicedb-migrate", "formbricks-migrate",
    "authzed-initialize", "hub-migrate", "permissions",
}
for nombre in sorted(esperados):
    if servicios.get(nombre, {}).get("restart") != "no":
        print(f"{nombre} debe declarar restart: 'no'", file=sys.stderr)
        sys.exit(1)
de_un_uso = sorted(n for n, s in servicios.items() if s.get("restart") == "no")
if not de_un_uso:
    print("no se encontro ningun servicio de un solo uso", file=sys.stderr)
    sys.exit(1)

for nombre in de_un_uso:
    consumidores = [
        otro for otro, s in servicios.items()
        if nombre in (s.get("depends_on") or {})
    ]
    if not consumidores:
        print(f"{nombre} es de un solo uso y nadie depende de el", file=sys.stderr)
        sys.exit(1)
    for otro in consumidores:
        condicion = (servicios[otro]["depends_on"][nombre] or {}).get("condition")
        if condicion != "service_completed_successfully":
            print(
                f"{otro} depende de {nombre} con condition={condicion!r};"
                " se esperaba 'service_completed_successfully'",
                file=sys.stderr,
            )
            sys.exit(1)
print("ok")
PY
  [ "$status" -eq 0 ] || {
    echo "${output}" >&2
    return 1
  }
}

@test "el chequeo Coolify acepta el compose sin sanitizarlo" {
  run bash scripts/coolify-check.sh
  [ "$status" -eq 0 ] || {
    echo "${output}" >&2
    return 1
  }
}
