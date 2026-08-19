# Repository Hardening Design

## Goal

Make the public repository safe to maintain and publish without changing its core product model: a dependency-free local Shadowrocket script and plain-text macOS configuration.

## Scope

The hardening release will:

- preserve unsupported Apple WLoc responses byte-for-byte when no recognized Wi-Fi or cell location was rewritten;
- reject location metadata that cannot be encoded as a safe signed 64-bit protobuf varint, with user-facing accuracy limited to `1...1000000` metres;
- remove secrets and coordinates from normal diagnostics and redact sensitive HTTP headers and URL query strings in opt-in debug dumps;
- make module generation atomic, reject unsafe output targets and incomplete CLI options, and keep the committed example module synchronized;
- add cross-platform CI, GitHub Actions dependency updates, security reporting, structured issue intake, contribution guidance, and ownership metadata;
- keep `main` protected by pull requests and CI, enable the available public-repository security features, and publish a checksum-backed `v0.1.0` pre-release.

## Runtime behavior

`spoofAppleResponse` may return rewritten bytes only when at least one structurally valid Wi-Fi or supported cell record has been patched. A parseable response with zero recognized records is unsupported and must return the original response unchanged. Exceptions remain fail-open in the Shadowrocket runtime.

All numeric values written as signed protobuf varints must be safe integers inside the signed 64-bit range. Latitude, longitude, and altitude retain their current domain limits. Horizontal and vertical accuracy accept integers from `1` through `1000000` metres in both the shell generator and JavaScript runtime.

Debug logging must never print configuration tokens, raw script arguments, target coordinates, URL query strings, `Authorization`, `Proxy-Authorization`, `Cookie`, or `Set-Cookie` values. Raw binary dumping remains an explicit advanced option and must emit a sensitivity warning.

## Tooling behavior

The generator writes a temporary file in the destination directory, verifies that output is non-empty and has no unresolved placeholders, then atomically renames it. Output must end in `.sgmodule` and must not resolve to the module template. An option that expects a value rejects another `--option` token as a missing value.

Diagnostics print only the module name, configured rule names, and exact MITM hostname line. They check all four supported hosts and avoid printing proxy addresses. The verification suite covers the new regressions, compares the generated example against `dist/`, and cleans temporary state even when dependencies are missing.

## Repository automation and governance

CI runs `./macos-shadowrocket/verify.sh` on Ubuntu and macOS with Node.js 18 and the current LTS, uses read-only permissions, has a timeout, and pins GitHub-authored Actions to immutable commit SHAs. Dependabot tracks the `github-actions` ecosystem weekly.

The repository adds concise `SECURITY.md`, `CONTRIBUTING.md`, issue forms, a pull-request template, and `CODEOWNERS`. Public issue forms explicitly prohibit CA material, private keys, tokens, sensitive coordinates, raw payloads, and unsanitized logs.

After CI succeeds, repository settings will use squash-only merges, automatic branch updates and cleanup, secret scanning and push protection where the public-repository plan exposes them, private vulnerability reporting, CodeQL default setup, and a `main` ruleset requiring a pull request, resolved conversations, and the CI check. Because there is one maintainer, the initial approval count is zero.

## Release

The first release is `v0.1.0`, marked pre-release because compatibility has been verified on one macOS/Shadowrocket combination. Release assets include the script, example module, a source archive assembled for users, and `SHA256SUMS`. No personalized module, coordinate file, certificate, key, token, or diagnostic log may enter the release.

## Verification

Completion requires:

- observed red-to-green regression tests for each runtime and generator defect;
- the full local verification suite on the final branch;
- successful GitHub Actions checks on the pull request;
- a clean privacy scan of tracked files and release assets;
- confirmation through the GitHub API that the requested repository settings are active;
- verification that the release tag and uploaded checksums match the published assets.
