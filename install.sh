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

INSTANCE_NAME="${1:-}"
REPO="victorblanco-tech/ai-assistant"

# Colors — 256-color palet (universele support ipv truecolor)
#   B = accent (ANSI 208 — warme oranje, Claude-style)
#   G = groen (success), Y = amber (warn), R = rood (error)
if [ -t 1 ]; then
  B=$'\033[38;5;208m'   # warme oranje (208 in 256-color)
  G=$'\033[38;5;42m'    # groen
  Y=$'\033[38;5;214m'   # amber/gold
  R=$'\033[38;5;203m'   # zacht rood
  N=$'\033[0m'
else
  G=""; Y=""; R=""; B=""; N=""
fi

echo
echo "${B}╔══════════════════════════════════╗${N}"
echo "${B}║   VB Tech Platform — Installer   ║${N}"
echo "${B}╚══════════════════════════════════╝${N}"
echo

# --- Instance-keuze: prompt als geen arg, anders gebruik arg ---
if [ -z "$INSTANCE_NAME" ]; then
  if [ ! -e /dev/tty ]; then
    # Geen TTY = fallback naar prod (bv. CI-pipeline)
    INSTANCE_NAME="prod"
  else
    echo "Welke omgeving wil je installeren?"
    echo "  ${B}1${N}) ${B}prod${N}  — main branch, voor klanten / eigen productie"
    echo "  ${B}2${N}) ${B}test${N}  — dev branch, voor release-testing"
    echo "  ${B}3${N}) ${B}dev${N}   — dev branch, voor ontwikkeling"
    echo
    printf "  Keuze [1]: "
    read -r choice </dev/tty
    case "${choice:-1}" in
      1|prod) INSTANCE_NAME="prod" ;;
      2|test) INSTANCE_NAME="test" ;;
      3|dev)  INSTANCE_NAME="dev"  ;;
      *)      echo "${R}✗${N} Ongeldige keuze: $choice" >&2; exit 2 ;;
    esac
    echo
  fi
fi

# Voor prod = main branch (stable), voor test/dev = dev branch
case "$INSTANCE_NAME" in
  dev|test) BRANCH="dev" ;;
  prod|*)   BRANCH="main" ;;
esac

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
