#!/usr/bin/env bash
# Public bootstrap. Platform source remains in the authorized private repository.
set +x
set -euo pipefail
umask 077

main() {
TOKEN="${GITHUB_TOKEN:-}"
unset GITHUB_TOKEN
INSTALLER_VERSION="1.2.2"
PLATFORM_REF="v0.26.1"
REF_SET=0
REPO="victorblanco-tech/ai-assistant"
INSTANCE_NAME="prod"
OWNER=""
CHECK_ONLY=0
SYSTEM_ARGS=()
INSTANCE_SET=0
STAGING=""

B=""; G=""; Y=""; N=""
if [ -t 1 ]; then
  B=$'\033[38;5;208m'; G=$'\033[38;5;42m'; Y=$'\033[38;5;214m'; N=$'\033[0m'
fi
printf '\n%s╔══════════════════════════════════╗\n' "$B"
printf '║   VB Tech Platform — Installer   ║\n'
printf '╚══════════════════════════════════╝%s\n' "$N"
printf '  Installer versie: %s%s%s\n\n' "$B" "$INSTALLER_VERSION" "$N"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
usage() {
  printf '%s\n' \
    'VB Tech installer 1.2.2 (macOS, fresh installations only)' \
    'Usage: bash install.sh [INSTANCE] [--check] [--ref=vX.Y.Z|40-character-commit]' \
    '       [--owner-email=EMAIL] [--system-env=PUBLIC_KEY=value] ...' \
    'Interactive environment menu: prod uses v0.26.1; test/dev use the dev branch.' \
    'The selected source is resolved once to an exact commit before setup.' \
    '--check only checks local prerequisites; no downloads or changes.' \
    'GitHub token: silent terminal prompt, or inherited GITHUB_TOKEN.' \
    'Existing instances are never overwritten; use their supported updater.'
}

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --check) CHECK_ONLY=1 ;;
    --ref=*) PLATFORM_REF="${arg#*=}"; REF_SET=1 ;;
    --owner-email=*) OWNER="${arg#*=}" ;;
    --system-env=*) SYSTEM_ARGS+=("$arg") ;;
    -*) fail "Unknown option (use --help)" ;;
    *) [ "$INSTANCE_SET" = 0 ] || fail "Only one instance name is allowed"
       INSTANCE_NAME="$arg"; INSTANCE_SET=1 ;;
  esac
done
[[ "$INSTANCE_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || fail "Invalid instance name"
[[ "$PLATFORM_REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$PLATFORM_REF" =~ ^[0-9a-f]{40}$ ]] \
  || fail "Select a stable tag or full commit, not a moving branch"
if [ "$CHECK_ONLY" = 0 ]; then
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    fail "An interactive terminal is required. Use --check for read-only preflight."
  fi
  if [ "$INSTANCE_SET" = 0 ]; then
    while :; do
      printf 'Welke omgeving wil je installeren?\n'
      printf '  %s1%s) %sprod%s — stabiele platformversie\n' "$B" "$N" "$B" "$N"
      printf '  %s2%s) %stest%s — dev branch, voor release-testing\n' "$B" "$N" "$B" "$N"
      printf '  %s3%s) %sdev%s  — dev branch, voor ontwikkeling\n' "$B" "$N" "$B" "$N"
      printf '  0) Afsluiten\n\n  Keuze [1]: ' >&3
      IFS= read -r choice <&3 || return 0
      case "${choice:-1}" in
        1|prod) INSTANCE_NAME="prod"; break ;;
        2|test) INSTANCE_NAME="test"; break ;;
        3|dev) INSTANCE_NAME="dev"; break ;;
        0|q|Q) return 0 ;;
        *) printf 'Kies 1, 2, 3 of 0.\n\n' ;;
      esac
    done
  fi
fi
if [ "$REF_SET" = 0 ]; then
  case "$INSTANCE_NAME" in dev|test) PLATFORM_REF=dev ;; esac
fi
printf '\n  Omgeving: %s%s%s | Platform: %s\n\n' "$B" "$INSTANCE_NAME" "$N" "$PLATFORM_REF"

check_prerequisites() {
printf '%s▸ Checking prerequisites...%s\n' "$B" "$N"
missing=0
needs() { printf '  %s[!]%s %s\n' "$Y" "$N" "$*"; missing=1; }
[ "$(uname -s)" = Darwin ] || needs "This installer supports macOS only."
[ "$(id -u)" != 0 ] || needs "Run as your normal user, not sudo/root."
for tool in git python3 node docker; do
  if command -v "$tool" >/dev/null; then
    printf '  %s[OK]%s %s found\n' "$G" "$N" "$tool"
  else
    case "$tool" in
      git) needs "Git missing. Install the Apple Command Line Tools: xcode-select --install" ;;
      python3) needs "Python 3 missing. Install Python 3: https://www.python.org/downloads/macos/" ;;
      node) needs "Node.js missing. Install Node.js 22 or newer: https://nodejs.org/" ;;
      docker) needs "Docker missing. Install and start Docker Desktop: https://www.docker.com/products/docker-desktop/" ;;
    esac
  fi
done
if command -v node >/dev/null; then
  node -e 'if(Number(process.versions.node.split(".")[0])<22)process.exit(1)' \
    || needs "Node.js 22 or newer is required. Update Node.js before continuing."
fi
if command -v docker >/dev/null; then
  docker info >/dev/null 2>&1 || needs "Docker is not ready. Start Docker Desktop and wait until it is running."
  docker compose version >/dev/null 2>&1 || needs "Docker Compose v2 is required. Check your Docker Desktop installation."
fi
if [ "$missing" = 1 ]; then
  printf '\nSetup has not started. Resolve the items above, then check again.\n'
  printf 'No files, services or settings have been changed.\n\n'
  return 1
fi
printf '\n%s[OK] Alle vereisten zijn aanwezig.%s\n\n' "$G" "$N"
}

if [ "$CHECK_ONLY" = 1 ]; then
  check_prerequisites || return 1
else
  check_label='Start check for pre-req'
  while :; do
    printf '  %s1%s) %s\n  0) Afsluiten\n\n' "$B" "$N" "$check_label"
    printf '  Actie [1]: ' >&3
    IFS= read -r choice <&3 || return 0
    case "${choice:-1}" in
      1)
        if check_prerequisites; then break; fi
        check_label='Opnieuw controleren (Start check for pre-req)'
        ;;
      0|q|Q) printf 'Installer afgesloten. Er is niets geinstalleerd.\n'; return 0 ;;
      *) printf 'Kies 1 om te controleren of 0 om af te sluiten.\n\n' ;;
    esac
  done
fi

VB_ROOT="${VB_ROOT:-$HOME/vb-tech}"
export VB_ROOT
INSTANCE_DIR="$VB_ROOT/instances/$INSTANCE_NAME"
# Reject ambiguous destinations, including symlinked parents, before mkdir/clone.
python3 - "$VB_ROOT" "$INSTANCE_DIR" <<'PY'
import os, pathlib, sys
root, target = map(pathlib.Path, sys.argv[1:])
if not root.is_absolute() or '..' in root.parts or root == pathlib.Path('/'):
    sys.exit('Unsafe installation root')
if any(p.is_symlink() for p in [target, *target.parents]):
    sys.exit('Symlinked installation paths are not supported')
if os.path.lexists(target):
    sys.exit('Instance already exists; use its supported updater, not this installer')
PY
printf 'Installer %s | Platform %s | Target %s\n' "$INSTALLER_VERSION" "$PLATFORM_REF" "$INSTANCE_DIR"
if [ "$CHECK_ONLY" = 1 ]; then
  printf 'Local prerequisites OK. Credentials and external services were not tested.\n'
  exit 0
fi

prompt() {
  printf '%s: ' "$1" >&3
  IFS= read -r REPLY <&3 || fail "Terminal input ended"
  [ -n "$REPLY" ] || fail "A value is required"
}
if [ -z "$OWNER" ]; then prompt 'Initial owner email'; OWNER="$REPLY"; fi

need_setting() {
  local key="$1" label="$2" entry
  for entry in ${SYSTEM_ARGS[@]+"${SYSTEM_ARGS[@]}"}; do
    case "$entry" in "--system-env=$key="*) return ;; esac
  done
  prompt "$label"
  SYSTEM_ARGS+=("--system-env=$key=$REPLY")
}
for prefix in MC PROJECTS KNOWLEDGE_SEARCH; do
  need_setting "${prefix}_ACCESS_TEAM_DOMAIN" "$prefix Cloudflare Access team domain (team.cloudflareaccess.com)"
  need_setting "${prefix}_ACCESS_AUDIENCE" "$prefix Access application audience (AUD)"
  need_setting "${prefix}_PUBLIC_ORIGIN" "$prefix HTTPS origin (without trailing slash)"
done
need_setting CRM_ACCESS_AUDIENCE 'CRM allowed audiences (include MC and Projects AUDs, comma-separated)'

printf '\nThis downloads authorized private source and runs its setup.\n' >&3
printf 'Setup builds/starts containers and asks for service credentials.\n' >&3
printf 'Use an expiring GitHub token scoped to this repository: Contents read only.\n' >&3
printf 'The bootstrap token is not saved or passed to the platform setup.\n' >&3
prompt 'Type INSTALL to continue'
[ "$REPLY" = INSTALL ] || fail "Cancelled; no files changed"
if [ -z "$TOKEN" ]; then
  printf 'GitHub token (hidden): ' >&3
  IFS= read -rs TOKEN <&3 || fail "Token input ended"
  printf '\n' >&3
fi
[[ "$TOKEN" =~ ^[A-Za-z0-9_]+$ ]] || fail "Invalid or empty GitHub token"

cleanup() { [ -z "$STAGING" ] || rm -rf -- "$STAGING"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$VB_ROOT/instances"
STAGING=$(mktemp -d "$VB_ROOT/instances/.bootstrap.XXXXXXXX")

# Secret exists only in the Git child environment, never argv or the remote URL.
credential_helper='!f() { if [ "$1" = get ]; then
  protocol= host= path=
  while IFS="=" read -r key value; do
    case "$key" in protocol) protocol=$value;; host) host=$value;; path) path=$value;; esac
  done
  if [ "$protocol" = https ] && [ "$host" = github.com ] && [ "$path" = victorblanco-tech/ai-assistant.git ]; then
    printf "username=x-access-token\npassword=%s\n" "$GITHUB_TOKEN"
  fi
fi; }; f'
auth_git() {
  GITHUB_TOKEN="$TOKEN" GIT_TERMINAL_PROMPT=0 GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 \
    git -c credential.helper= -c credential.useHttpPath=true \
    -c "credential.helper=$credential_helper" -c http.followRedirects=false \
    -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@"
}
git init -q "$STAGING/source"
git -C "$STAGING/source" remote add origin "https://github.com/$REPO.git"
case "$PLATFORM_REF" in
  dev) FETCH_REF=refs/heads/dev ;;
  v*) FETCH_REF="refs/tags/$PLATFORM_REF" ;;
  *) FETCH_REF="$PLATFORM_REF" ;;
esac
printf 'Fetching platform source...\n'
auth_git -C "$STAGING/source" fetch --quiet --depth=1 origin "$FETCH_REF" \
  || fail "Source access failed. Check token permissions, expiry and selected release."
COMMIT=$(git -C "$STAGING/source" rev-parse 'FETCH_HEAD^{commit}')
git -C "$STAGING/source" checkout --quiet --detach "$COMMIT"
unset TOKEN
[ -f "$STAGING/source/setup.sh" ] && [ ! -L "$STAGING/source/setup.sh" ] || fail "Release has no regular setup.sh"
grep -q -- '--bootstrap-commit=' "$STAGING/source/setup.sh" || fail "This release does not support the fresh bootstrap contract"

# Use the selected release's own validator; do not duplicate its access rules.
node - "$STAGING/source" "$OWNER" ${SYSTEM_ARGS[@]+"${SYSTEM_ARGS[@]}"} <<'JS'
const path = require('node:path');
const [root, owner, ...args] = process.argv.slice(2);
const { validateFreshIdentity, publicKeys } = require(path.join(root, 'containers/app-system/ops/provision-environment.cjs'));
const values = {};
for (const prefix of ['MC', 'PROJECTS', 'KNOWLEDGE_SEARCH']) {
  values[prefix === 'MC' ? 'MC_BOOTSTRAP_OWNER_EMAIL' : `${prefix}_OWNER_EMAILS`] = owner;
}
for (const arg of args) {
  const assignment = arg.slice('--system-env='.length), equal = assignment.indexOf('=');
  const key = assignment.slice(0, equal), value = assignment.slice(equal + 1);
  if (equal < 1 || !publicKeys.includes(key) || Object.hasOwn(values, key) || /[\r\n\0"'`$\\]/.test(value)) {
    throw new Error('Invalid, duplicate or unsupported public system setting');
  }
  values[key] = value;
}
validateFreshIdentity(values);
JS

python3 - "$STAGING/source" "$INSTANCE_DIR" <<'PY'
import os, sys
source, target = sys.argv[1:]
if os.path.lexists(target):
    sys.exit('Destination appeared during preparation; refusing overwrite')
os.rename(source, target)
PY
printf 'Selected platform commit: %s\n' "$COMMIT"
printf 'If setup fails, the prepared checkout stays in %s for inspection.\n' "$INSTANCE_DIR"
bash "$INSTANCE_DIR/setup.sh" "$INSTANCE_NAME" "--bootstrap-commit=$COMMIT" \
  --initialize-fresh-app-system "--system-owner-email=$OWNER" ${SYSTEM_ARGS[@]+"${SYSTEM_ARGS[@]}"}
}

main "$@"
