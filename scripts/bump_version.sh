#!/usr/bin/env bash
set -euo pipefail

PUBSPEC_FILE="${1:-pubspec.yaml}"

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

if ! [[ "$current_code" =~ ^[0-9]+$ ]]; then
  echo "invalid versionCode: $current_code" >&2
  exit 1
fi

next_code=$((current_code + 1))
next_version="${base_version}+${next_code}"

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

echo "Bumped version: ${current_version} -> ${next_version}"
