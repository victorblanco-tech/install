#!/usr/bin/env bash
# =============================================================================
# VB Tech Platform — Bootstrap installer
#
# Publieke stub die de private repo clonet en setup.sh erbinnen uitvoert.
# Wordt gehost op: https://github.com/victorblanco-tech/install
#
# Gebruik:
#   curl -fsSL https://raw.githubusercontent.com/victorblanco-tech/install/main/install.sh | bash
#
# Optioneel: instance-naam meegeven (default: prod):
#   curl -fsSL https://... | bash -s -- test
#
# Optioneel: token als env-var (geen prompt):
#   GITHUB_TOKEN=xxx curl -fsSL https://... | bash
# =============================================================================
set -euo pipefail

INSTANCE_NAME="${1:-prod}"
REPO="victorblanco-tech/ai-assistant"
# Voor prod = main branch (stable), voor test/dev = dev branch
case "$INSTANCE_NAME" in
  dev|test) BRANCH="dev" ;;
  prod|*)   BRANCH="main" ;;
esac

# Colors
if [ -t 1 ]; then
  G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; B=$'\033[0;34m'; N=$'\033[0m'
else
  G=""; Y=""; R=""; B=""; N=""
fi

echo
echo "${B}╔═════════════════════════════╗${N}"
echo "${B}║   VB Tech Platform — Installer   ║${N}"
echo "${B}╚═════════════════════════════╝${N}"
echo "  Instance: ${B}$INSTANCE_NAME${N} (branch: $BRANCH)"
echo

# Preflight
command -v git >/dev/null  || { echo "${R}✗${N} git niet geinstalleerd" >&2; exit 1; }
command -v curl >/dev/null || { echo "${R}✗${N} curl niet geinstalleerd" >&2; exit 1; }

# Token: uit env OF interactief
if [ -z "${GITHUB_TOKEN:-}" ]; then
  if [ ! -e /dev/tty ]; then
    echo "${R}✗${N} GITHUB_TOKEN vereist (geen TTY voor prompt)" >&2
    echo "   Gebruik: GITHUB_TOKEN=xxx curl ... | bash" >&2
    exit 1
  fi
  echo "${Y}!${N} Private repo — GitHub token nodig (krijg je van Victor)"
  echo "   Format: github_pat_xxx..."
  printf "   Token: "
  read -r GITHUB_TOKEN </dev/tty
fi

[ -z "$GITHUB_TOKEN" ] && { echo "${R}✗${N} Token vereist" >&2; exit 1; }

# Download setup.sh uit private repo met token
echo
echo "${B}▸${N} Download setup.sh van ${REPO} (branch: ${BRANCH})"
TMPFILE=$(mktemp /tmp/vbtech-setup.XXXXXX.sh)
trap "rm -f $TMPFILE" EXIT

if ! curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
     "https://raw.githubusercontent.com/${REPO}/${BRANCH}/setup.sh" -o "$TMPFILE"; then
  echo "${R}✗${N} Download gefaald. Token ongeldig of geen repo-toegang?" >&2
  exit 1
fi

chmod +x "$TMPFILE"
echo "${G}✓${N} Download OK ($(wc -l < "$TMPFILE") regels)"

# Run setup.sh — GITHUB_TOKEN via env zodat setup.sh de clone kan doen
echo
exec env GITHUB_TOKEN="$GITHUB_TOKEN" bash "$TMPFILE" "$INSTANCE_NAME"
