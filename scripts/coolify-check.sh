#!/usr/bin/env bash
# Aceptación: verifica que los compose del kit puedan correr bajo Coolify/Traefik.
#
# Para cada compose del contrato:
#   1. Parsea el YAML con python para detectar:
#        - `name:` raíz en el archivo fuente (Coolify lo reemplaza).
#        - Redes y volúmenes con `name:` propio (Coolify pone los nombres).
#        - Variables usadas con `${VAR}`, `${VAR:-x}`, `${VAR:?msg}` y similares.
#   2. Genera un .env temporal con valores ficticios no secretos por cada variable:
#        - variables de host/URL → https://ejemplo.invalid
#        - resto → string `x123...`
#   3. Renderiza el compose con `docker compose --format json`. Debe pasar sin error.
#   4. Con jq comprueba el contrato Coolify en los servicios sin `profiles`:
#        - sin `ports:`, `container_name`, `privileged`, `cap_add`, `devices`
#        - sin `network_mode: host`, `pid: host`, `ipc: host`
#        - sin `security_opt` con `unconfined`
#        - sin bind a `docker.sock` ni absoluto fuera del repo.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Composes bajo contrato: "<base_dir_relativo>:<archivo>".
# Este kit es postgres-local, base raíz y un único compose.
readonly -a COMPOSES=(
    ".:compose.yaml"
)

# Servicios one-shot que Coolify debe tolerar en exited 0 vía exclude_from_hc.
# Docker Compose strict rechaza esta extensión; el script la sanitiza antes
# de renderizar y la verifica por separado.
readonly -a COOLIFY_ONESHOTS=(
    "authzed-db-bootstrap"
    "spicedb-migrate"
    "formbricks-migrate"
    "authzed-initialize"
    "hub-migrate"
    "permissions"
)

# Variables que se tratan como URL (toman https://ejemplo.invalid).
readonly URL_VARS_REGEX='^(WEBAPP_URL|NEXTAUTH_URL|CUBEJS_API_URL|HUB_API_URL|TAXONOMY_SERVICE_URL)$'

# Valor simulado no secreto (no es token, es texto plano evidente para detectar fugas).
readonly STUB='x1234567890123456789012345678901234567890123456789012345678901234'

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Comprueba las dependencias antes de tocar nada: si falta una, el error
# posterior ("no se pudo parsear", "jq no encontrado") confunde y oculta la
# causa real.
command -v docker >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1 \
    || fail "falta docker (con el plugin compose v2)"
docker compose version >/dev/null 2>&1 2>&1 \
    || fail "falta docker compose v2 (docker compose version no responde)"
command -v jq >/dev/null 2>&1 || fail "falta jq"
command -v python3 >/dev/null 2>&1 || fail "falta python3"
python3 -c 'import yaml' 2>/dev/null || fail "falta python3-yaml (PyYAML)"

cd "$REPO_ROOT"

# Directorio de trabajo temporal único por ejecución; mktemp evita pisar o
# colisionar con otras sesiones paralelas y con un symlink preexistente.
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/coolify-check.XXXXXX")"
# DOCKER_CONFIG redirige a un HOME de docker escribible: silencia el warning
# "permission denied" sobre ~/.docker/config.json sin tocar el del usuario.
export DOCKER_CONFIG="$WORKDIR/docker-config"
mkdir -p "$DOCKER_CONFIG"
trap 'rm -rf "$WORKDIR"' EXIT

# Extrae del YAML fuente, en una sola pasada:
#   - `name` raíz (si existe).
#   - nombres de volúmenes y redes con `name:` propio.
#   - variables tipo `${VAR}`, `${VAR:-x}` y `${VAR:?msg}` en cualquier string.
extract_yaml_meta() {
    local compose_file="$1"
    python3 - "$REPO_ROOT/$base_dir/$compose_file" <<'PY'
import re, sys, json, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh) or {}

pat = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)")
vars_ = set()
def walk(node):
    if isinstance(node, dict):
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
    elif isinstance(node, str):
        for m in pat.findall(node):
            vars_.add(m)
walk(doc)

bad_v = sorted(k for k, v in (doc.get("volumes") or {}).items()
               if isinstance(v, dict) and v.get("name"))
bad_n = sorted(k for k, v in (doc.get("networks") or {}).items()
               if isinstance(v, dict) and v.get("name"))

print(json.dumps({
    "name": doc.get("name"),
    "named_volumes": bad_v,
    "named_networks": bad_n,
    "vars": sorted(vars_),
}))
PY
}

# Genera una copia del compose sin las extensiones de Coolify que el esquema
# strict de Docker Compose rechaza (exclude_from_hc). Coolify las lee del
# archivo original; esta copia se pasa solo a `docker compose config`.
strip_coolify_extensions() {
    local src="$1"
    local dst="$2"
    python3 - "$src" "$dst" <<'PY'
import sys, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh) or {}
removed = 0
for name, svc in (doc.get("services") or {}).items():
    if isinstance(svc, dict) and "exclude_from_hc" in svc:
        del svc["exclude_from_hc"]
        removed += 1
with open(sys.argv[2], "w") as fh:
    yaml.safe_dump(doc, fh, default_flow_style=False, sort_keys=False)
print(f"sanitized: dropped exclude_from_hc on {removed} service(s)", file=sys.stderr)
PY
}

# Comprueba que los one-shots declarados en COOLIFY_ONESHOTS llevan
# exclude_from_hc en el compose original (no en la copia sanitizada).
check_coolify_extensions() {
    local compose_path="$1"
    COOLIFY_ONESHOTS_STR="${COOLIFY_ONESHOTS[*]}"
    export COOLIFY_ONESHOTS_STR
    COOLIFY_COMPOSE_PATH="$compose_path"
    export COOLIFY_COMPOSE_PATH
    python3 - <<'PY'
import os, sys, yaml
oneshots = os.environ["COOLIFY_ONESHOTS_STR"].split()
with open(os.environ["COOLIFY_COMPOSE_PATH"]) as fh:
    doc = yaml.safe_load(fh) or {}
services = doc.get("services") or {}
missing = [s for s in oneshots
           if not isinstance(services.get(s), dict)
           or services[s].get("exclude_from_hc") is not True]
if missing:
    print("faltan exclude_from_hc en: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY
}

# Comprueba que el servicio web `formbricks` declara healthcheck en el compose
# fuente (no en la copia sanitizada). Coolify lo usa para detectar cuándo la
# app está lista; sin él, el proxy recibe tráfico antes de que el proceso
# esté vivo y se cae el primer request.
check_formbricks_healthcheck() {
    local compose_path="$1"
    COOLIFY_COMPOSE_PATH="$compose_path"
    export COOLIFY_COMPOSE_PATH
    python3 - <<'PY'
import os, sys, yaml
with open(os.environ["COOLIFY_COMPOSE_PATH"]) as fh:
    doc = yaml.safe_load(fh) or {}
svc = (doc.get("services") or {}).get("formbricks")
if not isinstance(svc, dict):
    print("servicio formbricks ausente del compose", file=sys.stderr)
    sys.exit(1)
if not isinstance(svc.get("healthcheck"), dict):
    print("formbricks sin healthcheck", file=sys.stderr)
    sys.exit(1)
PY
}

# Comprueba que los tres disables de flujo de correo están parametrizados en
# el compose fuente: la cadena `VAR: '0'` literal no debe aparecer; deben
# usar la forma `${VAR:-0}` para que Coolify pueda inyectar 1 sin tocar el
# compose. Las vars validadas: EMAIL_VERIFICATION_DISABLED,
# PASSWORD_RESET_DISABLED, INVITE_DISABLED.
check_disables_parametrized() {
    local compose_path="$1"
    COOLIFY_COMPOSE_PATH="$compose_path"
    export COOLIFY_COMPOSE_PATH
    COOLIFY_DISABLE_VARS_STR="EMAIL_VERIFICATION_DISABLED PASSWORD_RESET_DISABLED INVITE_DISABLED"
    export COOLIFY_DISABLE_VARS_STR
    python3 - <<'PY'
import os, re, sys
with open(os.environ["COOLIFY_COMPOSE_PATH"]) as fh:
    text = fh.read()
hardcoded = re.compile(r"^\s*(?P<k>EMAIL_VERIFICATION_DISABLED|PASSWORD_RESET_DISABLED|INVITE_DISABLED):\s*'0'\s*$",
                       re.MULTILINE)
hits = hardcoded.findall(text)
if hits:
    print("disables hardcoded '0' en compose: " + ", ".join(sorted(set(hits))), file=sys.stderr)
    sys.exit(1)
# Además, cada disable debe aparecer al menos una vez con la forma ${VAR:-...}
# para que Coolify pueda inyectar el valor real. Si solo aparecen como
# literales, no son parametrizables.
for var in os.environ["COOLIFY_DISABLE_VARS_STR"].split():
    pat = re.compile(r"\$\{\s*" + re.escape(var) + r"\s*:-")
    if not pat.search(text):
        print("disable no parametrizado: " + var, file=sys.stderr)
        sys.exit(1)
PY
}

# Ejecuta ops/check-env.cjs con SMTP_READY=false y los disables mínimos, y
# exige exit 0. Esto reproduce la rúbrica del README: el validador del
# servicio web NO aborta cuando el operador arranca sin SMTP y fija los dos
# disables obligatorios.
check_check_env_no_smtp() {
    local repo_root="$1"
    local check_env="$repo_root/ops/check-env.cjs"
    [[ -f "$check_env" ]] || fail "check-env.cjs no encontrado"

    # 64 chars hex no secretos para los cinco secrets requeridos.
    local hex64
    hex64="$(printf 'a%.0s' $(seq 1 64))"

    local rc=0
    WEBAPP_URL="https://ejemplo.invalid" \
        NEXTAUTH_URL="https://ejemplo.invalid" \
        NEXTAUTH_SECRET="$hex64" \
        ENCRYPTION_KEY="$hex64" \
        CRON_SECRET="$hex64" \
        HUB_API_KEY="$hex64" \
        CUBEJS_API_SECRET="$hex64" \
        OPERATOR_ACCOUNT_CREATED=true \
        SMTP_READY=false \
        EMAIL_VERIFICATION_DISABLED=1 \
        PASSWORD_RESET_DISABLED=1 \
        node "$check_env" > "$WORKDIR/check-env.out" 2> "$WORKDIR/check-env.err" \
        || rc=$?

    if [[ $rc -ne 0 ]]; then
        local out err
        out=$(cat "$WORKDIR/check-env.out" 2>/dev/null || true)
        err=$(cat "$WORKDIR/check-env.err" 2>/dev/null || true)
        fail "check-env.cjs aborta con SMTP_READY=false (rc=${rc}): stdout=${out} stderr=${err}"
    fi
}

check_compose() {
    local base_dir="$1"
    local compose_file="$2"
    local env_file="$WORKDIR/.env"
    : > "$env_file"

    local compose_path="$REPO_ROOT/$base_dir/$compose_file"
    if [[ ! -f "$compose_path" ]]; then
        fail "${base_dir}/${compose_file}: archivo inexistente"
    fi

    # Comprueba las extensiones de Coolify sobre el compose ORIGINAL.
    check_coolify_extensions "$compose_path" \
        || fail "${compose_file}: uno o más one-shots sin exclude_from_hc (Coolify los tolera en exited 0)"

    # Comprueba que el servicio web tiene healthcheck (sin él, el proxy
    # recibe tráfico antes de que el proceso esté listo).
    check_formbricks_healthcheck "$compose_path" \
        || fail "${compose_file}: el servicio web formbricks debe declarar healthcheck"

    # Comprueba que los tres disables de correo están parametrizados
    # (no hardcoded '0') para que Coolify pueda inyectar el valor real.
    check_disables_parametrized "$compose_path" \
        || fail "${compose_file}: los disables de correo deben estar parametrizados con \${VAR:-0}"

    # Comprueba que el validador del servicio web (check-env.cjs) acepta
    # arrancar con SMTP_READY=false y los dos disables obligatorios.
    check_check_env_no_smtp "$REPO_ROOT" \
        || fail "${compose_file}: check-env.cjs aborta con SMTP_READY=false (verificá EMAIL_VERIFICATION_DISABLED y PASSWORD_RESET_DISABLED)"

    # Genera copia sanitizada para pasar a `docker compose config`,
    # que con esquema strict rechaza exclude_from_hc.
    local sanitized="$WORKDIR/compose.sanitized.yaml"
    strip_coolify_extensions "$compose_path" "$sanitized" \
        || fail "${compose_file}: no se pudo sanear el YAML"

    # Validar YAML fuente: nada de `name:` raíz ni volúmenes/redes con `name:`.
    local meta
    meta=$(extract_yaml_meta "$compose_file") || fail "${compose_file}: no se pudo parsear"
    echo "$meta" > "$WORKDIR/meta.json"

    if [[ "$(jq -r '.name // empty' "$WORKDIR/meta.json")" != "" ]]; then
        fail "${compose_file}: 'name' a nivel raíz no permitido (Coolify asigna el nombre del proyecto)"
    fi

    if [[ "$(jq -r '.named_volumes | length' "$WORKDIR/meta.json")" != "0" ]]; then
        fail "${compose_file}: volúmenes con 'name' fijo: $(jq -r '.named_volumes | join(", ")' "$WORKDIR/meta.json")"
    fi
    if [[ "$(jq -r '.named_networks | length' "$WORKDIR/meta.json")" != "0" ]]; then
        fail "${compose_file}: redes con 'name' fijo: $(jq -r '.named_networks | join(", ")' "$WORKDIR/meta.json")"
    fi

    # Lista de variables extraídas del YAML fuente.
    local vars
    vars=$(jq -r '.vars[]' "$WORKDIR/meta.json")
    if [[ -z "$vars" ]]; then
        fail "${compose_file}: no se encontraron variables de entorno"
    fi

    # Excluye COMPOSE_PROJECT_NAME: Coolify controla el nombre del proyecto desde
    # fuera con `--project-name`/`-p`; meterla en el .env simulado haría que el
    # render la inyecte como `name:` raíz y enmascare el chequeo anterior.
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        [[ "$v" == "COMPOSE_PROJECT_NAME" ]] && continue
        if [[ "$v" =~ $URL_VARS_REGEX ]]; then
            echo "${v}=https://ejemplo.invalid" >> "$env_file"
        else
            echo "${v}=${STUB}" >> "$env_file"
        fi
    done <<< "$vars"

    # Renderiza a JSON. Captura stdout y stderr por separado.
    local rc=0
    docker compose \
        --project-directory "$REPO_ROOT/$base_dir" \
        -f "$sanitized" \
        --env-file "$env_file" \
        config --format json \
        > "$WORKDIR/doc.json" \
        2> "$WORKDIR/err" || rc=$?

    if [[ $rc -ne 0 ]]; then
        local rendered_err
        rendered_err=$(cat "$WORKDIR/err")
        fail "${compose_file}: render falló (exit=${rc}): ${rendered_err}"
    fi

    if ! jq . "$WORKDIR/doc.json" > "$WORKDIR/doc.pretty.json" 2>/dev/null; then
        fail "${compose_file}: salida de config no es JSON válido"
    fi
    mv "$WORKDIR/doc.pretty.json" "$WORKDIR/doc.json"

    # Recorre servicios sin `profiles` y valida el contrato.
    local services
    services=$(jq -r '
        .services | to_entries
        | map(select((.value.profiles // []) | length == 0))
        | map(.key) | .[]' "$WORKDIR/doc.json")

    for svc in $services; do
        local s="$WORKDIR/svc.json"
        jq --arg k "$svc" '.services[$k]' "$WORKDIR/doc.json" > "$s"

        if jq -e 'has("ports")' "$s" >/dev/null; then
            fail "${svc}: campo 'ports' no permitido en servicios sin profiles"
        fi
        if jq -e 'has("container_name")' "$s" >/dev/null; then
            fail "${svc}: campo 'container_name' no permitido en servicios sin profiles"
        fi
        if jq -e '(.privileged // false) == true' "$s" >/dev/null; then
            fail "${svc}: campo 'privileged' no permitido"
        fi
        if jq -e 'has("cap_add")' "$s" >/dev/null; then
            fail "${svc}: campo 'cap_add' no permitido"
        fi
        if jq -e 'has("devices")' "$s" >/dev/null; then
            fail "${svc}: campo 'devices' no permitido"
        fi
        if [[ "$(jq -r '.network_mode // ""' "$s")" == "host" ]]; then
            fail "${svc}: network_mode: host no permitido"
        fi
        if [[ "$(jq -r '.pid // ""' "$s")" == "host" ]]; then
            fail "${svc}: pid: host no permitido"
        fi
        if [[ "$(jq -r '.ipc // ""' "$s")" == "host" ]]; then
            fail "${svc}: ipc: host no permitido"
        fi
        if jq -e '.security_opt // [] | any(. == "unconfined" or (type == "string" and test("unconfined")))' "$s" >/dev/null; then
            fail "${svc}: security_opt 'unconfined' no permitido"
        fi

        # binds prohibidos: docker.sock o rutas absolutas fuera del repo.
        local binds
        binds=$(jq -r '
            (.volumes // [])[]
            | select(type == "object" and (.type // "bind") == "bind")
            | .source // ""' "$s")
        while IFS= read -r src; do
            [[ -z "$src" ]] && continue
            if [[ "$src" == "/var/run/docker.sock" || "$src" == "/var/run/docker/"* ]]; then
                fail "${svc}: bind a ${src} no permitido (docker.sock)"
            fi
            if [[ "$src" == /* ]]; then
                case "$src" in
                    "$REPO_ROOT"/*) : ;;
                    *) fail "${svc}: bind absoluto fuera del repo: ${src}" ;;
                esac
            fi
        done <<< "$binds"
    done
}

for entry in "${COMPOSES[@]}"; do
    IFS=':' read -r base_dir compose_file <<< "$entry"
    check_compose "$base_dir" "$compose_file"
done

echo "OK: ${#COMPOSES[@]} compose(s) cumplen el contrato Coolify"
