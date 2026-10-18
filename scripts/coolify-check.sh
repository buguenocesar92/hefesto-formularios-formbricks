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

# Variables que se tratan como URL (toman https://ejemplo.invalid).
readonly URL_VARS_REGEX='^(WEBAPP_URL|NEXTAUTH_URL|CUBEJS_API_URL|HUB_API_URL|TAXONOMY_SERVICE_URL)$'

# Valor simulado no secreto (no es token, es texto plano evidente para detectar fugas).
readonly STUB='x1234567890123456789012345678901234567890123456789012345678901234'

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

cd "$REPO_ROOT"

# Directorio de trabajo temporal (reutilizable si hay reintentos).
WORKDIR="${TMPDIR:-/tmp}/coolify-check"
mkdir -p "$WORKDIR"
DOCKER_CFG="$WORKDIR/docker-config"
mkdir -p "$DOCKER_CFG"
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

check_compose() {
    local base_dir="$1"
    local compose_file="$2"
    local env_file="$WORKDIR/.env"
    : > "$env_file"

    local compose_path="$REPO_ROOT/$base_dir/$compose_file"
    if [[ ! -f "$compose_path" ]]; then
        fail "${base_dir}/${compose_file}: archivo inexistente"
    fi

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
        -f "$compose_file" \
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
