#!/usr/bin/env bash
set -euo pipefail

CLI_URL="URL_MAD_CLI"
TMP_DIR="${BITRISE_DEPLOY_DIR:-/tmp}/mad-android-cli-$$"
ZIP_FILE="${TMP_DIR}/mad_android_cli_1.7.1.zip"
CLI_DIR="${TMP_DIR}/cli"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "❌ MAD Android Step failed: $*" >&2
  exit 1
}

require_input() {
  local name="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || fail "Required input '$name' is empty."
}

require_input "license_key" "${license_key:-}"
require_input "cli_path" "${cli_path:-}"
require_input "file" "${file:-}"
require_input "config" "${config:-}"
require_input "store_file" "${store_file:-}"
require_input "store_password" "${store_password:-}"
require_input "key_alias" "${key_alias:-}"
require_input "key_password" "${key_password:-}"

[[ -f "$file" ]] || fail "Input file does not exist: $file"
[[ -f "$config" ]] || fail "MAD config does not exist: $config"
[[ -f "$store_file" ]] || fail "Keystore does not exist: $store_file"
[[ -e "$cli_path" ]] || fail "cli_path does not exist: $cli_path. The MAD CLI must be available on the runner before this Step executes (e.g. checked out from a private repository or restored from cache in an earlier Step)."

case "$file" in
  *.apk|*.APK|*.aab|*.AAB) ;;
  *) fail "Input file must be an APK or AAB: $file" ;;
esac

if [[ -d "$cli_path" ]]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64)
      CLI="$(find "$cli_path" -maxdepth 2 -type f -iname '*-linux' | head -n 1)"
      ;;
    aarch64|arm64)
      CLI="$(find "$cli_path" -maxdepth 2 -type f -iname '*-arm64' | head -n 1)"
      ;;
    *)
      fail "Unsupported runner architecture: $ARCH"
      ;;
  esac
  [[ -n "$CLI" && -f "$CLI" ]] || fail "Could not find a MAD CLI binary for architecture $ARCH inside cli_path: $cli_path"
elif [[ -f "$cli_path" ]]; then
  CLI="$cli_path"
else
  fail "cli_path must be a file or a directory: $cli_path"
fi

chmod +x "$CLI"

echo "==> MAD CLI: $("$CLI" --help 2>&1 | head -n 1 || true)"
echo "==> Protecting Android artifact..."

"$CLI" \
  --license-key "$license_key" \
  --file "$file" \
  --config "$config" \
  --store-file "$store_file" \
  --store-password "$store_password" \
  --key-alias "$key_alias" \
  --key-password "$key_password"

if [[ -n "${output_file:-}" ]]; then
  if [[ -f "$output_file" ]]; then
    protected="$output_file"
  else
    echo "⚠️ output_file was supplied but does not exist after MAD execution; falling back to output detection."
    protected=""
  fi
else
  protected=""
fi

if [[ -z "$protected" ]]; then
  input_dir="$(cd "$(dirname "$file")" && pwd)"
  input_base="$(basename "$file")"
  input_name="${input_base%.*}"
  input_ext="${input_base##*.}"

  for candidate in \
    "$input_dir/${input_name}-mad.${input_ext}" \
    "$input_dir/${input_name}-protected.${input_ext}" \
    "$input_dir/${input_name}_mad.${input_ext}" \
    "$input_dir/${input_name}_protected.${input_ext}" \
    "$input_dir/${input_name}.${input_ext}"
  do
    if [[ -f "$candidate" && "$candidate" != "$file" ]]; then
      protected="$candidate"
      break
    fi
  done
fi

if [[ -z "$protected" ]]; then
  input_dir="$(cd "$(dirname "$file")" && pwd)"
  while IFS= read -r candidate; do
    if [[ "$candidate" != "$file" ]]; then
      protected="$candidate"
      break
    fi
  done < <(find "$input_dir" -maxdepth 1 -type f \( -iname '*.apk' -o -iname '*.aab' \) -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)
fi

if [[ -z "$protected" || ! -f "$protected" ]]; then
  fail "MAD CLI finished, but no protected APK/AAB could be identified. Check the MAD CLI output and generated artifacts."
fi

export MAD_OUTPUT_FILE="$protected"
envman add --key MAD_OUTPUT_FILE --value "$protected"

echo "✅ MAD protection completed."
echo "MAD_OUTPUT_FILE=$protected"
