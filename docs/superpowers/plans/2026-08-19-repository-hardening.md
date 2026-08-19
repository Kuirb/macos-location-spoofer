# Repository Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix fail-open and privacy defects, harden module generation, add CI/community safeguards, configure the public GitHub repository, and publish a verified `v0.1.0` pre-release.

**Architecture:** Keep the single-file Shadowrocket runtime and dependency-free shell workflow. Add validation at both input boundaries, prove every defect with regression tests, keep generated output deterministic, and place repository policy in `.github/` plus GitHub settings rather than expanding the landing README.

**Tech Stack:** ES2020-compatible JavaScript, Node.js built-in test utilities, Bash 3.2-compatible shell, Shadowrocket `.sgmodule`, GitHub Actions, GitHub REST/GraphQL APIs.

## Global Constraints

- Repository visibility remains Public.
- No macOS application, Xcode project, npm dependency, CA, private key, token, personal coordinate, raw payload, or unsanitized diagnostic log may be added.
- Horizontal and vertical accuracy accept integer metres in the inclusive range `1...1000000` in shell and JavaScript.
- Unsupported responses with zero recognized rewritten records are returned byte-for-byte unchanged.
- CI actions use immutable full commit SHAs and workflows declare `permissions: contents: read`.
- Existing supported envelopes, four exact MITM hosts, local `location-spoofer.js` loading, AGPL-3.0-only licensing, and bilingual README parity remain intact.
- Local test documentation requires Node.js 22 or later; CI tests exact major versions 22 and 24.

---

### Task 1: Protocol fail-open and integer safety

**Files:**
- Modify: `location-spoofer.js`
- Modify: `macos-shadowrocket/test-protocol.js`

**Interfaces:**
- Consumes: `spoofAppleResponse(bytes, config)`, `normalizeConfig(input)`, `encodeVarintSignedInt64(value)`.
- Produces: byte-preserving zero-record behavior and safe signed-int64 encoding used by later runtime tests.

- [ ] **Step 1: Add failing zero-record and numeric-boundary tests**

Add fixed-byte assertions equivalent to:

```js
const unsupported = Uint8Array.from(Buffer.from("000100000001000000021801", "hex"));
const unsupportedResult = spoofer.spoofAppleResponse(unsupported, target);
assert.equal(unsupportedResult.wifiCount + unsupportedResult.cellCount, 0);
assert.deepEqual(unsupportedResult.response, unsupported);

assert.throws(
  () => spoofer.normalizeConfig({ horizontalAccuracy: 1000001 }),
  /invalid horizontal accuracy/
);
assert.throws(
  () => spoofer.encodeVarintSignedInt64(1000000000000000000000000000000),
  /safe integer|signed int64/
);
```

- [ ] **Step 2: Run the protocol test and confirm the expected failures**

Run: `node macos-shadowrocket/test-protocol.js`

Expected: the zero-record response differs from the fixture and/or the oversized integer is accepted.

- [ ] **Step 3: Implement minimal fail-open and integer validation**

Add shared JavaScript constants for `MAX_ACCURACY_METRES = 1000000`, signed-int64 bounds, and a safe-integer validator. Make `encodeVarintSignedInt64` reject unsafe numeric inputs and values outside signed int64. Make `normalizeConfig` require safe integer accuracy within `1...1000000` and safe integers for every other integer metadata field. In `spoofAppleResponse`, return the original response bytes when `wifiCount + cellCount === 0`.

- [ ] **Step 4: Run protocol and full verification tests**

Run: `node macos-shadowrocket/test-protocol.js && ./macos-shadowrocket/verify.sh`

Expected: both commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add location-spoofer.js macos-shadowrocket/test-protocol.js
git commit -m "Preserve unsupported location responses"
```

### Task 2: Runtime diagnostic privacy and header correctness

**Files:**
- Modify: `location-spoofer.js`
- Modify: `macos-shadowrocket/test-runtime.js`

**Interfaces:**
- Consumes: Task 1 numeric validation and existing `runRuntime` harness.
- Produces: sanitized diagnostic logging and case-insensitive response header replacement.

- [ ] **Step 1: Add failing privacy and lowercase-header tests**

Add runtime cases that use sentinel values `SENSITIVE_CONFIG_TOKEN`, `SENSITIVE_COOKIE`, and `SENSITIVE_QUERY`. Assert none occur in logs when debug/dump options are enabled; assert header logs contain `[REDACTED]`; assert URL logs contain no query string; assert a lowercase input `content-type` is replaced without producing two case variants; and assert decompression failure emits no log when `debug=false`.

```js
assert.equal(result.logs.some((line) => line.includes("SENSITIVE_CONFIG_TOKEN")), false);
assert.equal(result.logs.some((line) => line.includes("SENSITIVE_COOKIE")), false);
assert.equal(Object.keys(result.result.headers).filter((name) => name.toLowerCase() === "content-type").length, 1);
```

- [ ] **Step 2: Run the runtime test and confirm sensitive values or duplicate headers fail assertions**

Run: `node macos-shadowrocket/test-runtime.js`

Expected: at least one new privacy/header assertion fails against the unmodified runtime.

- [ ] **Step 3: Implement minimal log redaction**

Replace raw argument logging with a key/presence summary. Never log the resolved config URL or target coordinates. Strip URL query/fragment text before logging. Copy headers through a case-insensitive sanitizer that redacts `authorization`, `proxy-authorization`, `cookie`, and `set-cookie`. Gate decompression diagnostics on `config.debug`. Make raw dumps emit a warning and require explicit debug plus `dumpRaw`.

- [ ] **Step 4: Normalize binary response headers case-insensitively**

When rebuilding headers, omit existing `content-type`, `content-length`, `content-encoding`, and `transfer-encoding` regardless of case, then add one canonical `Content-Type` and `Content-Length`.

- [ ] **Step 5: Run runtime and full verification tests**

Run: `node macos-shadowrocket/test-runtime.js && ./macos-shadowrocket/verify.sh`

Expected: both commands exit 0 with no sensitive sentinel in output.

- [ ] **Step 6: Commit**

```bash
git add location-spoofer.js macos-shadowrocket/test-runtime.js
git commit -m "Redact runtime diagnostics"
```

### Task 3: Atomic generation, private diagnostics, and deterministic distribution

**Files:**
- Modify: `macos-shadowrocket/generate-module.sh`
- Modify: `macos-shadowrocket/diagnose.sh`
- Modify: `macos-shadowrocket/observe-locationd.sh`
- Modify: `macos-shadowrocket/verify.sh`
- Modify: `.gitignore`
- Create: `.gitattributes`
- Modify: `README.md`
- Modify: `README.en.md`

**Interfaces:**
- Consumes: accuracy limit from Task 1.
- Produces: atomic `.sgmodule` output, sanitized module summaries, and a verification command consumed by CI.

- [ ] **Step 1: Add failing shell regression checks**

Extend `verify.sh` before production shell changes to assert:

```bash
# generator rejects 1000001, --output --help, non-.sgmodule output, and the template path
# a valid generated file contains no __PLACEHOLDER__ token
# generated example is byte-identical to dist/macos-location-spoofer.sgmodule
# diagnostic module-summary output contains no latitude=, longitude=, configToken=, or argument=
# exact MITM hostname line contains all four hosts and no extra host
```

Move the Node dependency check before temporary-directory creation so the test can verify clean early exit.

- [ ] **Step 2: Run `./macos-shadowrocket/verify.sh` and confirm the new checks fail**

Expected: the oversized accuracy, unsafe output, or diagnostic privacy assertion fails.

- [ ] **Step 3: Implement atomic generator output**

Require `.sgmodule`, reject an option token where a value is expected, canonicalize the destination parent, reject the template as output, create a same-directory temporary file, render to it, require non-empty output with no `__[A-Z_]+__` tokens, then `mv` it into place. Clean the temporary file on every signal or error. Validate accuracy with `in_range "$value" 1 1000000`.

- [ ] **Step 4: Sanitize diagnostics and complete host checks**

Add a `--module-summary PATH` mode to `diagnose.sh` that prints only `#!name`, rule names as configured, and the exact hostname line, then exits. Use the same summary in the normal diagnostic path. Report only proxy enable flags, check all four hosts, and print root-relative commands. Make `observe-locationd.sh` retain useful error output and warn that streamed metadata must be sanitized before sharing.

- [ ] **Step 5: Extend ignore and line-ending policy**

Ignore `*.p12`, `*.pfx`, `*.der`, `*.mobileconfig`, `.env`, and `.env.*` while allowing `.env.example`. Add `.gitattributes` entries enforcing LF for shell, JavaScript, configuration, and module files.

- [ ] **Step 6: Update both READMEs without expanding their structure**

Change accuracy ranges to `1...1000000`, require Node.js 22+, state that diagnostics are sanitized by default but still need review, and keep Chinese/English facts aligned.

- [ ] **Step 7: Run the full verification suite and distribution comparison**

Run: `./macos-shadowrocket/verify.sh && git diff --check`

Expected: both commands exit 0 and the committed `dist/` module matches generated example output.

- [ ] **Step 8: Commit**

```bash
git add .gitignore .gitattributes README.md README.en.md macos-shadowrocket/generate-module.sh macos-shadowrocket/diagnose.sh macos-shadowrocket/observe-locationd.sh macos-shadowrocket/verify.sh
git commit -m "Harden module tooling and diagnostics"
```

### Task 4: GitHub automation and community safety

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/dependabot.yml`
- Create: `.github/CODEOWNERS`
- Create: `.github/pull_request_template.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/compatibility_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `SECURITY.md`
- Create: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: Task 3 `./macos-shadowrocket/verify.sh` contract.
- Produces: the `verify` status check required by the `main` ruleset and safe public contribution channels.

- [ ] **Step 1: Resolve immutable GitHub Action SHAs**

Use GitHub API tag refs for the selected major releases of `actions/checkout` and `actions/setup-node`, dereferencing annotated tags when necessary. Record each full 40-character commit SHA with an inline release comment.

- [ ] **Step 2: Create the CI workflow**

Use `pull_request`, `push` to `main`, manual dispatch, read-only permissions, concurrency cancellation, and a matrix of `ubuntu-latest`/`macos-14` with Node.js `22`/`24`. Set `timeout-minutes: 10`, `persist-credentials: false`, run `./macos-shadowrocket/verify.sh`, `git diff --check`, and assert the worktree remains clean.

- [ ] **Step 3: Add Dependabot and ownership**

Configure weekly `github-actions` updates at directory `/`. Assign `*`, `/.github/`, `/location-spoofer.js`, `/macos-shadowrocket/`, `/LICENSE`, and `/NOTICE` to `@Kuirb` without requiring CODEOWNER approval in branch rules.

- [ ] **Step 4: Add concise security and contribution guidance**

`SECURITY.md` supports `main` and the latest release, directs reports to GitHub private vulnerability reporting, and forbids public secrets/location artifacts. `CONTRIBUTING.md` requires the verification script, bilingual fact parity, AGPL attribution, and sanitized fixtures.

- [ ] **Step 5: Add structured Issue Forms and PR template**

Bug and compatibility forms require macOS version, architecture, Shadowrocket version, exact `/clls/wloc`/MITM/patch observations, and a mandatory checkbox confirming sanitization. Disable blank issues and link security reports to `/security/advisories/new`. The PR template requires tests, distribution synchronization, bilingual docs, and a secrets/privacy check.

- [ ] **Step 6: Validate YAML and repository policy files**

Parse all `.yml` files using an available YAML parser, verify every Action reference uses a 40-character SHA, scan policy files for placeholders, then run `./macos-shadowrocket/verify.sh && git diff --check`.

- [ ] **Step 7: Commit**

```bash
git add .github SECURITY.md CONTRIBUTING.md
git commit -m "Add repository safety automation"
```

### Task 5: Publish, enforce settings, and release

**Files:**
- No source changes unless CI or review finds a defect.

**Interfaces:**
- Consumes: Tasks 1-4 and the successful `verify` GitHub Actions check.
- Produces: merged hardening PR, active repository protections, and verified `v0.1.0` pre-release.

- [ ] **Step 1: Perform final branch review and verification**

Run the full local suite, privacy scan, generated distribution comparison, YAML validation, and whole-branch code review. Fix every Critical/Important finding before publishing.

- [ ] **Step 2: Push and open a ready-for-review hardening PR**

Push `agent/repository-hardening`, create a PR against `main`, include root causes, user impact, validations, and setting changes. Wait for every matrix job to complete successfully.

- [ ] **Step 3: Apply repository settings**

Keep Public visibility; set squash-only merges; enable branch updates, auto-merge, and delete-on-merge; disable unused Projects. Enable public-repository Dependabot alerts/security updates, secret scanning, push protection, validity checks where exposed, private vulnerability reporting, and CodeQL default setup. Restrict Actions to approved GitHub-authored actions and require SHA pinning.

- [ ] **Step 4: Create the `main-protection` ruleset**

Target `refs/heads/main`; require a pull request, resolved conversations, linear history, and the exact successful `verify` check; block deletions and force pushes; require zero approvals while `Kuirb` is the only maintainer; do not require CODEOWNER review.

- [ ] **Step 5: Squash-merge the hardening PR and verify `main`**

Merge only at the reviewed head SHA, confirm CI and settings through GitHub APIs, and confirm the remote feature branch is deleted.

- [ ] **Step 6: Build and verify release assets**

Create a clean archive containing `location-spoofer.js`, `dist/macos-location-spoofer.sgmodule`, `README.md`, `README.en.md`, `LICENSE`, and `NOTICE`; generate `SHA256SUMS`; scan filenames and contents for private artifacts; independently recompute every checksum.

- [ ] **Step 7: Publish `v0.1.0` as a pre-release**

Create the release from the merged `main` commit with compatibility scope, four-host MITM warning, fail-open warning, install/uninstall pointer, and attached archive, script, module, and checksum file. Verify tag target, pre-release state, assets, sizes, and downloaded checksums through GitHub.
