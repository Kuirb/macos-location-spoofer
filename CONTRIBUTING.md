# Contributing

Use Node.js 22 or later, then run:

```sh
./macos-shadowrocket/verify.sh
git diff --check
```

Keep `README.md` and `README.en.md` factually equivalent. Contributions are under AGPL-3.0-only; retain required attribution and notices.

Use sanitized, minimal fixtures only. Never commit personal coordinates, secrets, certificates, private keys, raw payloads, or diagnostic logs. When generated module content changes, regenerate and commit the matching `dist/macos-location-spoofer.sgmodule` output.
