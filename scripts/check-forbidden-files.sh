#!/usr/bin/env bash
# Fails if files that usually hold secrets or signing material are tracked by git.
# Run by CI next to the gitleaks secret scan; safe to run locally too.
set -euo pipefail
cd "$(dirname "$0")/.."

patterns=(
  '(^|/)\.env(\..+)?$'              # environment files (.env, .env.local, …)
  '\.(p12|pfx|pem|key|p8|cer)$'     # certificates, private keys, App Store Connect API keys
  '\.(mobileprovision|provisionprofile)$'
  '\.keychain(-db)?$'
  '(^|/)id_(rsa|dsa|ecdsa|ed25519)$'  # SSH private keys
  '(^|/)\.netrc$'
)

found=$(git ls-files | grep -E "$(IFS='|'; echo "${patterns[*]}")" || true)
if [[ -n "$found" ]]; then
  echo "These tracked files can contain secrets or signing material:"
  echo "$found" | sed 's/^/  /'
  echo "Remove them from git (and rotate anything they contained), then add them to .gitignore."
  exit 1
fi
echo "No forbidden files tracked."
