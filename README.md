# MAD Android Bitrise Step

Bitrise Step for protecting Android APK/AAB artifacts with MAD Android CLI 1.7.1.

## Inputs

- `license_key`: MAD license key (sensitive)
- `file`: input APK/AAB
- `config`: `mad_config.xml`
- `store_file`: Android keystore
- `store_password`: keystore password (sensitive)
- `key_alias`: signing key alias
- `key_password`: signing key password (sensitive)

## Output

`MAD_OUTPUT_FILE` contains the path to the protected APK/AAB.

## Example

```yaml
workflows:
  deploy:
    steps:
      - gradle-runner:
          inputs:
            - gradle_task: bundleRelease

      - git::https://github.com/showmeyourhands/bitrise-mad-android.git@main:
          inputs:
            - license_key: $MAD_LICENSE_KEY
            - file: $BITRISE_AAB_PATH
            - config: $MAD_CONFIG_FILE
            - store_file: $MAD_STORE_FILE
            - store_password: $MAD_STORE_PASSWORD
            - key_alias: $MAD_KEY_ALIAS
            - key_password: $MAD_KEY_PASSWORD
```

The CLI is downloaded from:

`https://madclifiles.s3.sa-east-1.amazonaws.com/mad_android_cli_1.7.1.zip`

The Step selects the Linux x86_64 or Linux ARM64 binary based on `uname -m`.

## Important

MAD CLI 1.7.1 does not expose an output-file CLI argument in its usage. The Step therefore detects the generated APK/AAB after execution. If the actual MAD output naming differs from the candidates in `step.sh`, adjust the detection block to the naming used by the CLI.

Do not commit MAD license keys, keystore passwords, or key passwords. Store them as Bitrise Secrets.
