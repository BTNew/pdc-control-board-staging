#!/usr/bin/env bash
# Install pg_safeupdate 1.5 into the Postgres server the SQL proofs use.
# Authenticator sessions preload this library. The official postgres:16
# service image does not ship it, and neither does a stock local server.
set -euo pipefail
exec 9>/tmp/pg-safeupdate-install.lock
flock 9

psql_super() {
  if [ -n "${PGHOST:-}" ]; then
    psql -h "$PGHOST" -U "${PGUSER:-postgres}" -d postgres -v ON_ERROR_STOP=1 "$@"
  else
    sudo -u postgres psql -d postgres -v ON_ERROR_STOP=1 "$@"
  fi
}

if psql_super -c "LOAD 'safeupdate';" >/dev/null 2>&1; then
  exit 0
fi

src="$(mktemp -d)"
trap 'rm -rf "$src"' EXIT
curl -fsSL -o "$src/safeupdate.c" https://raw.githubusercontent.com/eradman/pg-safeupdate/1.5/safeupdate.c
curl -fsSL -o "$src/Makefile" https://raw.githubusercontent.com/eradman/pg-safeupdate/1.5/Makefile
echo '986515e91c4963a81ba211cae8a02079e62e0278678a894a9660797830f30cdf  safeupdate.c' | (cd "$src" && sha256sum -c -)
echo 'ef5096abbd961a5520e72e756a0828e78fcd1ff1dfdf3fed9435bc785747b159  Makefile' | (cd "$src" && sha256sum -c -)
grep -q 'DELETE requires a WHERE clause' "$src/safeupdate.c"

install_docker() {
  local cid
  cid="$(docker ps --format '{{.ID}} {{.Image}}' | awk '/postgres:16/ {print $1; exit}')"
  if [ -z "$cid" ]; then
    return 1
  fi
  docker exec -u root "$cid" mkdir -p /tmp/pg-safeupdate
  docker cp "$src/safeupdate.c" "$cid:/tmp/pg-safeupdate/safeupdate.c"
  docker cp "$src/Makefile" "$cid:/tmp/pg-safeupdate/Makefile"
  docker exec -u root "$cid" bash -c 'apt-get update && apt-get install -y --no-install-recommends build-essential postgresql-server-dev-16 && make -C /tmp/pg-safeupdate install'
}

if [ -n "${PGHOST:-}" ] && command -v docker >/dev/null 2>&1; then
  install_docker
else
  sudo apt-get update -qq
  sudo apt-get install -y -qq postgresql-server-dev-16 build-essential
  sudo make -C "$src" install
fi

psql_super -c "LOAD 'safeupdate';"
