#!/usr/bin/env bash
set -euo pipefail

CLI_URL="https://madclifiles.s3.sa-east-1.amazonaws.com/mad_android_cli_1.7.1.zip"
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
require_input "file" "${file:-}"
require_input "config" "${config:-}"
require_input "store_file" "${store_file:-}"
require_input "store_password" "${store_password:-}"
require_input "key_alias" "${key_alias:-}"
require_input "key_password" "${key_password:-}"

[[ -f "$file" ]] || fail "Input file does not exist: $file"
[[ -f "$config" ]] || fail "MAD config does not exist: $config"
[[ -f "$store_file" ]] || fail "Keystore does not exist: $store_file"

case "$file" in
  *.apk|*.APK|*.aab|*.AAB) ;;
  *) fail "Input file must be an APK or AAB: $file" ;;
esac

mkdir -p "$CLI_DIR"

echo "==> Downloading MAD Android CLI 1.7.1..."
curl --fail --location --retry 3 --silent --show-error \
  "$CLI_URL" -o "$ZIP_FILE"

echo "==> Extracting MAD Android CLI..."
unzip -q "$ZIP_FILE" -d "$CLI_DIR"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    CLI="$CLI_DIR/mad_android_cli_1.7.1/mad-android-cli-1.7.1-linux"
    ;;
  aarch64|arm64)
    CLI="$CLI_DIR/mad_android_cli_1.7.1/mad-android-cli-1.7.1-arm64"
    ;;
  *)
    fail "Unsupported runner architecture: $ARCH"
    ;;
esac

[[ -f "$CLI" ]] || fail "MAD CLI binary not found for architecture $ARCH"
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

# Prefer an explicitly supplied output path if the CLI created it.
if [[ -n "${output_file:-}" ]]; then
  # The CLI interface shown by MAD 1.7.1 does not expose an output argument.
  # Therefore only accept this as the expected destination when it already exists.
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

  # Common MAD output naming candidates.
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
  # Find newly/modified APK/AAB files in the input directory, excluding the original.
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
