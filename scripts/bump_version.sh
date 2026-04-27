#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/bump_version.sh [pubspec.yaml] [major|minor|patch]
  scripts/bump_version.sh [major|minor|patch]

Defaults to pubspec.yaml and patch.

Examples:
  scripts/bump_version.sh patch
  scripts/bump_version.sh pubspec.yaml minor
  scripts/bump_version.sh pubspec.yaml major
USAGE
}

PUBSPEC_FILE="pubspec.yaml"
BUMP_PART="patch"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  case "$1" in
    major|minor|patch)
      BUMP_PART="$1"
      ;;
    *)
      PUBSPEC_FILE="$1"
      BUMP_PART="${2:-patch}"
      ;;
  esac
fi

case "$BUMP_PART" in
  major|minor|patch) ;;
  *)
    echo "unsupported bump part: $BUMP_PART" >&2
    usage >&2
    exit 1
    ;;
esac

if [[ ! -f "$PUBSPEC_FILE" ]]; then
  echo "pubspec file not found: $PUBSPEC_FILE" >&2
  exit 1
fi

current_line="$(awk '/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$/ {print; exit}' "$PUBSPEC_FILE")"
if [[ -z "$current_line" ]]; then
  echo "version line not found or unsupported format in $PUBSPEC_FILE" >&2
  exit 1
fi

current_version="${current_line#version: }"
base_version="${current_version%%+*}"
current_code="${current_version##*+}"

if ! [[ "$base_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "invalid versionName: $base_version" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

if ! [[ "$current_code" =~ ^[0-9]+$ ]]; then
  echo "invalid versionCode: $current_code" >&2
  exit 1
fi

case "$BUMP_PART" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
esac

next_code=$((current_code + 1))
next_version="${major}.${minor}.${patch}+${next_code}"

awk -v old="$current_line" -v new="version: ${next_version}" '
  BEGIN { replaced = 0 }
  {
    if (!replaced && $0 == old) {
      print new
      replaced = 1
    } else {
      print
    }
  }
  END {
    if (!replaced) {
      exit 1
    }
  }
' "$PUBSPEC_FILE" > "${PUBSPEC_FILE}.tmp"
mv "${PUBSPEC_FILE}.tmp" "$PUBSPEC_FILE"

echo "Bumped version (${BUMP_PART}): ${current_version} -> ${next_version}"
