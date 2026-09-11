---
name: 1password
user_invocable: true
description: Secure secret access via 1Password CLI — lookup, inject, and run with secrets from the user's 1Password vault
---

# /1password

Access secrets from the user's 1Password vault. All commands use `OP_BIOMETRIC_UNLOCK_ENABLED=true` for desktop app authentication.

## Which vault

The vault name is personal configuration, not part of this skill. Resolve it in order:

1. `$OP_VAULT` if set in the environment
2. The **1Password** section of the user's private profile at `$MEMORY_VAULT_PATH/personal/profile.md`
3. Otherwise ask the user — never guess or list every vault

Examples below write the vault as `"$OP_VAULT"`; substitute the resolved name.

## Safety Rules — MANDATORY

1. **Never output full secret values** to the conversation. If you must show a secret, mask it: show only the first 4 and last 4 characters (e.g., `ac6J...COHi`).
2. **Never store secrets in memory files** or vault notes. Secrets belong in 1Password only.
3. **Never log secrets** in issue comments, git commits, or any persisted artifact.
4. **Use `--fields`** to retrieve only the specific field needed — never dump entire items.
5. **Prefer `op run`** over `op item get` when a command needs a secret — this avoids the secret touching the shell.

## Operations

### Lookup a secret

```bash
OP_BIOMETRIC_UNLOCK_ENABLED=true op item get "<Item Name>" --vault "$OP_VAULT" --fields password
```

Use when: you need a specific secret value for a one-time operation (e.g., manual database connection).

### List vault contents

```bash
OP_BIOMETRIC_UNLOCK_ENABLED=true op item list --vault "$OP_VAULT"
```

Use when: browsing available secrets or verifying an item exists.

### Filter by tag

```bash
OP_BIOMETRIC_UNLOCK_ENABLED=true op item list --vault "$OP_VAULT" --tags database
```

Common tags: `database`, `api-key`, `cloud-service`, `vpn` (the profile lists the vault's actual tag set, if recorded).

### Inject secrets into .env

```bash
OP_BIOMETRIC_UNLOCK_ENABLED=true op inject -i .env.tpl -o .env --force
```

If the current project ships its own injection wrapper script, prefer it — check the project's docs.

Use when: populating `.env` from the template after a fresh clone, secret rotation, or `.env.tpl` change.

### Run a command with secrets

```bash
OP_BIOMETRIC_UNLOCK_ENABLED=true op run --env-file .env.tpl -- <command>
```

Use when: running a command that needs secrets without writing them to disk. Secrets are injected as environment variables for the subprocess only.

## Item Naming Convention

Follow the current project's item-to-env-var mapping document if it has one.

## Adding a New Secret

1. Create item: `OP_BIOMETRIC_UNLOCK_ENABLED=true op item create --category password --vault "$OP_VAULT" --title "<Name>" --tags <tag> "password=<value>"`
2. Add an `op://<vault>/<Name>/password` reference to `.env.tpl`
3. Update the project's item mapping document, if it has one
4. Re-run the injection step to regenerate `.env`
