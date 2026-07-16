# macOS Location Spoofer for Shadowrocket

**English** · [中文](README.md)

Rewrite Apple Wi-Fi positioning responses on macOS with Shadowrocket—without building a macOS app, using Xcode, or disabling System Integrity Protection (SIP).

This project intercepts a narrowly scoped set of Apple location-service requests, rewrites the coordinates in the binary response, and returns the result to Core Location. It is intended for development, testing, and research on Macs and networks you control.

> [!WARNING]
> This setup requires HTTPS decryption with a locally generated, trusted CA certificate. A trusted CA is security-sensitive and its trust is system-wide even though this module limits interception to four hosts. Generate your own certificate in Shadowrocket, never install a CA supplied by someone else, keep its private key local, and remove it when you are finished. Do not use this project for emergency location, navigation, safety tracking, access control, fraud, or unauthorized testing.

## Tested environment and scope

The proof of concept was verified on one specific setup:

- Apple Silicon Mac
- macOS 27.0 (26A5378j)
- Shadowrocket 2.2.90
- Apple Maps / Core Location

That setup confirmed the following path:

1. `locationd` sent requests to an Apple `/clls/wloc` endpoint.
2. Shadowrocket intercepted the request and response through scoped HTTPS decryption.
3. The script decoded and rewrote Wi-Fi positioning records.
4. Requesting the current location in Maps moved the displayed position to the configured coordinates.

This is not a universal compatibility guarantee. Apple uses an undocumented internal protocol, and behavior may differ by macOS version, Shadowrocket version, region, network, cache state, or application.

## How it works

```text
locationd
   │  HTTPS /clls/wloc
   ▼
Shadowrocket TUN + scoped MITM
   │
   ├─ request hook: ask for an uncompressed response
   └─ response hook: decode ARPC/protobuf, rewrite Wi-Fi and cell
                     location fields, then preserve the response framing
   ▼
Core Location / Maps
```

The response script is fail-open by default: if it cannot safely parse or rewrite a response, it returns the original response instead of intentionally breaking the location request. The original response may reveal the real location, so this project is not an anonymity system or fail-closed safety control.

This changes only a particular network-based positioning path. It does **not** emulate a GPS radio, change your public IP address, or guarantee that every app will use the modified location. Apps may use cached data, IP geolocation, account data, Bluetooth, their own backend, or another location source.

## Features

- No macOS app or Xcode project
- No SIP changes
- Plain-text `key=value` location configuration
- Latitude, longitude, altitude, horizontal accuracy, and vertical accuracy controls
- Wi-Fi and cell location-field rewriting in Apple WLoc responses
- Request preparation for compressed responses
- Strict module generation and configuration validation
- Generated module arguments remain authoritative and do not inherit generic keys from Shadowrocket's shared persistent store
- Local protocol/runtime tests with no npm dependencies
- Read-only diagnostic and `locationd` log helpers
- Local script loading by default instead of fetching JavaScript remotely

## Requirements

- A Mac with Location Services available
- [Shadowrocket for macOS](https://apps.apple.com/app/shadowrocket/id932747118)
- Permission to install and explicitly trust your own local CA certificate
- A Shadowrocket setup that routes `locationd` traffic through its TUN
- Node.js 18 or later only for the local test suite
- Standard macOS command-line tools (`bash`, `awk`, `sed`, `grep`)

No npm install is required.

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/Kuirb/macos-location-spoofer.git
cd macos-location-spoofer
```

### 2. Create your private plain-text configuration

```bash
cp macos-shadowrocket/location.example.conf macos-shadowrocket/location.conf
```

Edit `macos-shadowrocket/location.conf` in any plain-text editor:

```ini
latitude=37.3349
longitude=-122.00902
altitude=56
horizontal_accuracy=15
vertical_accuracy=25
debug=false
```

`location.conf` and generated personalized modules are ignored by Git. Keep them private: coordinates and debug logs can reveal sensitive location information.

For a plausible altitude, use a local map/topographic source or query an elevation service. For example:

```text
https://api.open-meteo.com/v1/elevation?latitude=37.3349&longitude=-122.00902
```

Elevation services commonly use terrain models and may not reflect a particular floor of a building. An approximate local ground elevation is normally more coherent than an unrelated fixed value.

Open-Meteo returns an array such as `{"elevation":[56.0]}`; use its first value. Its elevation API is based on the approximately 90-metre Copernicus DEM 2021 GLO-90 terrain model, not building-floor height, and the query sends the target coordinates to a third party. See the [Open-Meteo Elevation API documentation](https://open-meteo.com/en/docs/elevation-api).

### 3. Run the tests and generate the module

```bash
cd macos-shadowrocket
./verify.sh
./update-location.sh
```

The generated module is written to:

```text
macos-shadowrocket/generated/macos-location-spoofer.sgmodule
```

`dist/macos-location-spoofer.sgmodule` is a pre-generated module for the public Apple Park example values. It is useful for inspecting the expected output, but it is not personalized; generate your own module for normal use.

If you do not want to use a configuration file, `generate-module.sh --help` lists equivalent command-line options.

### 4. Install the local script in Shadowrocket

Copy the repository's root-level `location-spoofer.js` into Shadowrocket's local **Script** directory. The filename must remain exactly:

```text
location-spoofer.js
```

On macOS, you can usually open Shadowrocket's Documents or configuration folder from the app and place the file in its `Script` folder. Menu names can vary by release. The generated module intentionally uses a local `script-path=location-spoofer.js`; do not replace it with an untrusted remote URL.

### 5. Import and enable the module

Import this generated file into Shadowrocket and enable it:

```text
macos-shadowrocket/generated/macos-location-spoofer.sgmodule
```

The module contains both request and response hooks for the exact `/clls/wloc` path. It scopes HTTPS decryption to these four hosts:

```text
gs-loc.apple.com
gs-loc-cn.apple.com
bluedot.is.autonavi.com
bluedot.is.autonavi.com.gds.alibabadns.com
```

Do not broaden the MITM hostname list unless you have independently reviewed and accepted the security impact.

### 6. Generate, install, and trust your own CA

In Shadowrocket's HTTPS Decryption / Certificate settings (wording varies by version):

1. Generate a **new local CA** in Shadowrocket.
2. Install that CA on the Mac.
3. Open **Keychain Access** and find it in the **System** keychain—not only the login keychain.
4. Open the certificate, expand **Trust**, and explicitly set it to **Always Trust**.
5. Enable HTTPS decryption in Shadowrocket.
6. Confirm the imported module is enabled and its four MITM hostnames are active.

The repository does not include a CA certificate or private key. If you see unexpected certificate warnings in unrelated apps, stop, disable HTTPS decryption, and review the certificate and hostname scope before continuing.

### 7. Route traffic and request a fresh location

1. Enable Shadowrocket's TUN/VPN mode. If `locationd` bypasses the tunnel, try TUN-only routing (shown as proxy type **None** in some versions) and the relevant **Include All Networks** option. Leave **Enforce Routes** off unless your setup specifically requires it. These options affect system-wide routing; restore your previous values if connectivity changes.
2. Disconnect and reconnect Shadowrocket after importing or changing the module.
3. In **System Settings → Privacy & Security → Location Services**, turn Location Services on and allow Maps to use it.
4. Open Maps and click the current-location button.

Allow a short time for caches to refresh. Reopening Maps or toggling Location Services off and back on can request a fresher result.

## Plain-text configuration reference

`location.conf` accepts blank lines, full-line comments whose first non-space character is `#`, and these six keys only. Inline comments are not supported. Unknown, duplicate, missing, or invalid keys cause generation to fail; the file is parsed as data and is never executed as shell code.

| Key | Valid values | Meaning | Practical guidance |
| --- | --- | --- | --- |
| `latitude` | `-90` to `90` | Target latitude in decimal degrees | Required |
| `longitude` | `-180` to `180` | Target longitude in decimal degrees | Required |
| `altitude` | `-1000` to `20000` | Altitude in metres | Use a plausible local ground elevation; negative values are valid |
| `horizontal_accuracy` | Number greater than `0` | Reported horizontal uncertainty in metres | `10`–`50` is a reasonable starting range, not an acceptance guarantee |
| `vertical_accuracy` | Number greater than `0` | Reported vertical uncertainty in metres | `20`–`100` is a reasonable starting range when altitude is known |
| `debug` | `true` or `false` | Shadowrocket script diagnostics | Keep `false` except while troubleshooting |

After every change:

```bash
cd macos-shadowrocket
./update-location.sh
```

Then reload or re-import the generated module and reconnect Shadowrocket. Editing `location.conf` alone does not modify an already imported module.

You can use another config or output path without changing the repository files:

```bash
./update-location.sh \
  --config /path/to/my-location.conf \
  --output /path/to/my-location.sgmodule
```

## Verifying the setup

### Local validation

Run:

```bash
cd macos-shadowrocket
./verify.sh
```

This checks shell syntax, protocol rewriting, Shadowrocket runtime behavior, gzip handling, module output, input validation, and configuration-injection resistance. A successful run ends with:

```text
All macOS Shadowrocket checks passed.
```

The tests use synthetic fixtures; they validate the code, not your CA trust or live interception.

### Read-only environment diagnostics

```bash
./diagnose.sh
```

This reports the macOS/Shadowrocket environment, generated module presence, endpoint strings in `locationd`, DNS resolution, proxy state, and the `locationd` service state. It does not change system settings and cannot prove that your CA is trusted.

To watch relevant Core Location logs while clicking the current-location button in Maps:

```bash
./observe-locationd.sh
```

Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to stop.

### Shadowrocket debug flow

If the local checks pass but Maps does not move:

1. Temporarily set `debug=true` in `location.conf`.
2. Run `./update-location.sh` again.
3. Reload or re-import the generated module.
4. Reconnect Shadowrocket.
5. Open Shadowrocket's script logs, then request the current location in Maps.

Useful log lines include:

```text
Location spoofer intercept -> lat=..., lng=..., url=https://.../clls/wloc
Location spoofer patched N wifi devices, M cell towers, ...
```

Treat the setup as successful only when all three conditions hold:

1. Shadowrocket shows the `/clls/wloc` request as MITM.
2. The `patched` log reports `N + M > 0` across Wi-Fi and cell records.
3. Maps moves near the configured coordinates.

DNS resolution, a connection to a listed host, `verify.sh`, or `diagnose.sh` alone does not prove live rewriting. Debug logs and response headers may contain the target coordinates, so turn `debug=false`, regenerate, reload the module, and reconnect when troubleshooting is complete.

## Changing the location

1. Edit the six values in `macos-shadowrocket/location.conf`.
2. Run `./macos-shadowrocket/update-location.sh` from the repository root, or run `./update-location.sh` inside `macos-shadowrocket`.
3. Reload or re-import `generated/macos-location-spoofer.sgmodule` in Shadowrocket.
4. Reconnect Shadowrocket.
5. Request the current location again in Maps.

Keep altitude and accuracy values coherent with the destination. An obviously mismatched altitude does not prevent rewriting, but it produces an internally inconsistent location record.

## Restore the real location and uninstall

To restore normal behavior:

1. Disable or remove the **macOS Location Spoofer** module.
2. If HTTPS decryption was enabled only for this project, turn it off.
3. Disconnect and reconnect Shadowrocket.
4. Reopen Maps and request the current location; cached coordinates may take a short time to expire.

To remove the trust material completely:

1. Delete the locally generated CA from Shadowrocket.
2. Delete the matching certificate from the **System** keychain in Keychain Access.
3. Remove the imported module and local `location-spoofer.js` from Shadowrocket.
4. Delete your private `location.conf`, generated module, and any debug logs if you no longer need them.

Removing the certificate does not require changing SIP.

Only remove the CA that you generated for this setup. Removing it also disables any other Shadowrocket HTTPS-decryption rules that depend on the same CA. Do not delete unrelated system certificates or `/var/db/locationd`.

## Troubleshooting

| Symptom | Checks |
| --- | --- |
| No `/clls/wloc` entry or script log | Confirm the module is enabled, TUN is active, `locationd` is routed through it, and Maps requested the current location. Reconnect after module changes. |
| Script file not found | Put `location-spoofer.js` in Shadowrocket's local `Script` directory with the exact filename, then reload the module. |
| Requests appear, but the response is not rewritten | Check HTTPS decryption, System-keychain CA trust, all four MITM hosts, and the response hook. An OS update may also have changed the endpoint or payload. |
| Certificate errors | Stop interception. Verify that the certificate is your own CA, it is trusted in the System keychain, and MITM remains limited to the four listed hosts. Reissue it if necessary. |
| Logs say `patched 0 wifi devices` | The response contained no recognized Wi-Fi records. Retry on another network/region or macOS build; the payload may be unsupported. |
| Maps still shows the previous position | Regenerate and reload the module, reconnect Shadowrocket, request a fresh fix, and account for Core Location/Maps caching. |
| `update-location.sh` rejects the file | Use exactly the six documented `key=value` keys, without quotes or extra keys. Check ranges and duplicate entries. |
| Shadowrocket/VPN connectivity breaks | Disable the module first, reconnect, then review CA trust, route settings, and the Shadowrocket log. The rewrite is designed to fail open, but routing and certificate errors happen before the script can help. |

## Limitations

- Apple WLoc/ARPC is undocumented and may change without notice.
- This targets the exact four hosts and `/clls/wloc` path currently present in the module; other endpoints are untouched.
- Only recognized Wi-Fi and cell location records inside intercepted responses are rewritten.
- Core Location and applications may cache an earlier result.
- An app can use IP location, its own server, account metadata, Bluetooth, GPS hardware, or other signals instead.
- Certificate pinning, traffic bypass, or an incompatible response format can prevent interception.
- Shadowrocket UI labels and routing behavior vary between releases.
- The tested proof of concept does not imply compatibility with every Mac, region, application, or future macOS version.

Do not describe or rely on this project as “undetectable.” It changes one input to a larger location stack, and downstream services can compare it with other signals.

## Repository layout

| Path | Purpose |
| --- | --- |
| `location-spoofer.js` | Shadowrocket request/response script and WLoc protobuf rewriter |
| `macos-shadowrocket/location.example.conf` | Safe example for a private plain-text configuration |
| `macos-shadowrocket/update-location.sh` | Parse `location.conf` and regenerate the module |
| `macos-shadowrocket/generate-module.sh` | Validate explicit options and render a module |
| `macos-shadowrocket/module.template.sgmodule` | Auditable Shadowrocket module template |
| `macos-shadowrocket/generated/` | Ignored personalized module output |
| `dist/macos-location-spoofer.sgmodule` | Pre-generated module using the public example values |
| `macos-shadowrocket/test-protocol.js` | Envelope-preservation and location-metadata rewrite tests |
| `macos-shadowrocket/test-runtime.js` | Shadowrocket runtime, request, and gzip response tests |
| `macos-shadowrocket/verify.sh` | Complete local validation suite |
| `macos-shadowrocket/diagnose.sh` | Read-only macOS/Shadowrocket environment report |
| `macos-shadowrocket/observe-locationd.sh` | Filtered live `locationd` log stream |

## Development and tests

There is no dependency installation step. With Node.js available:

```bash
cd macos-shadowrocket
./verify.sh
```

Or run the JavaScript tests separately:

```bash
node macos-shadowrocket/test-protocol.js
node macos-shadowrocket/test-runtime.js
```

When changing the module template or generator, also inspect a generated module and confirm the script path, two hooks, exact URL pattern, and four-host MITM scope.

## Security and responsible use

- Use this project only on devices, accounts, and networks you own or are authorized to test.
- Follow applicable laws and the terms of the applications and services you use.
- Never publish your CA private key, personal coordinates, debug logs, or personalized generated module.
- Review `location-spoofer.js` and `module.template.sgmodule` before trusting or importing them.
- Keep HTTPS decryption scoped to the minimum required hosts and disable it when it is no longer needed.

## Credits and license

This project is derived from [mekos2772/ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer), which in turn credits [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer).

The 2026 macOS/Shadowrocket adaptation adds the plain-text generation workflow, scoped macOS module, request preparation, response-body compatibility handling, diagnostics, and tests. See `NOTICE` for the modification notice and attribution.

Licensed under the [GNU Affero General Public License v3.0](LICENSE). If you modify, run as a network service, or redistribute this software, review and comply with the AGPL-3.0 obligations. The software is provided without warranty.
