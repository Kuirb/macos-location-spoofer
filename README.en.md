# macOS Location Spoofer for Shadowrocket

**English** · [中文](README.md)

Rewrite Apple Wi-Fi positioning responses on macOS through Shadowrocket—without a macOS app, Xcode, or disabling SIP. It is intended for development and testing on Macs, accounts, and networks you own or are authorized to use.

> [!WARNING]
> HTTPS decryption requires a locally generated, system-trusted CA. This repository ships no CA or private key: create your own, keep it private, restrict MITM to the four hosts below, and remove it afterward. The rewriter is fail-open, so unsupported responses pass through unchanged and may reveal the real location. Never use this for navigation, emergencies, fraud, access control, or unauthorized testing.

**Tested:** Apple Silicon · macOS 27.0 (26A5378j) · Shadowrocket 2.2.90 · Apple Maps / Core Location. This is one verified setup, not a compatibility guarantee.

## Requirements

- A Mac with Location Services
- [Shadowrocket for macOS](https://apps.apple.com/app/shadowrocket/id932747118)
- Git and standard macOS command-line tools; Node.js 18+ only for local tests (no npm install)
- Permission to install/trust your own CA and a Shadowrocket TUN route that captures `locationd`

## Quick start

Clone, create a private config, validate, and generate a module:

```bash
git clone https://github.com/Kuirb/macos-location-spoofer.git
cd macos-location-spoofer
cp macos-shadowrocket/location.example.conf macos-shadowrocket/location.conf
${EDITOR:-nano} macos-shadowrocket/location.conf
./macos-shadowrocket/verify.sh
./macos-shadowrocket/update-location.sh
```

`location.conf` contains exactly six `key=value` entries:

```ini
latitude=37.3349
longitude=-122.00902
altitude=56
horizontal_accuracy=15
vertical_accuracy=25
debug=false
```

Ranges: latitude `-90...90`, longitude `-180...180`, altitude `-1000...20000` metres, and each accuracy at least `1` metre. Altitude and accuracy are truncated to integers at runtime; keep `debug=false` unless troubleshooting.

`macos-shadowrocket/location.conf` and personalized files under `macos-shadowrocket/generated/` are gitignored because they can reveal sensitive coordinates. Your generated module is `macos-shadowrocket/generated/macos-location-spoofer.sgmodule`.

### Configure Shadowrocket

1. Copy the root-level `location-spoofer.js` to Shadowrocket's local **Script** directory, preserving the filename.
2. Import and enable `macos-shadowrocket/generated/macos-location-spoofer.sgmodule`.
3. Generate a new local CA in Shadowrocket, install it in the macOS **System** keychain, and set it to **Always Trust**; the login keychain alone may not cover `locationd`.
4. Enable HTTPS decryption / MITM and HTTP/2 handling for these exact hosts:

   ```text
   gs-loc.apple.com
   gs-loc-cn.apple.com
   bluedot.is.autonavi.com
   bluedot.is.autonavi.com.gds.alibabadns.com
   ```

5. Enable TUN. If `locationd` bypasses it, try the relevant **Include All Networks** option and restore prior routing if connectivity changes.
6. Reconnect Shadowrocket. Turn on **System Settings → Privacy & Security → Location Services**, allow Maps, then request the current location.

Do not broaden the host list or replace the local script with an untrusted remote URL.

## Change the location

1. Edit the six values in `macos-shadowrocket/location.conf`.
2. Run `./macos-shadowrocket/update-location.sh`, then reload or re-import the generated module.
3. Reconnect Shadowrocket and request a fresh location in Maps.

Editing the config alone does not update an imported module; Core Location caching may also take a short time to refresh.

## Confirm that it works

Temporarily set `debug=true`, regenerate and reload the module, reconnect, then inspect Shadowrocket's script logs while Maps requests a fresh location. Success requires all three:

1. Shadowrocket shows the exact `/clls/wloc` request as **MITM**.
2. A log says `patched N wifi devices, M cell towers` with **N + M > 0**.
3. Maps moves near the configured coordinates.

Set `debug=false`, regenerate, reload, and reconnect afterward; logs and response headers may contain your target coordinates.

## How it works

- `locationd` requests Apple Wi-Fi positioning data from an exact `/clls/wloc` endpoint.
- Shadowrocket TUN and scoped MITM run the request and response hooks.
- The response hook decodes and rewrites recognized Wi-Fi and cell fields while preserving the binary response framing.
- Core Location receives the rewritten result for use by Maps and compatible clients.

This changes one network-based positioning path. It does not emulate GPS, change your public IP, or force every app to use the rewritten location.

## Troubleshooting

- **No request or script:** enable the module and TUN, confirm Maps requested current location, check the exact local script filename, then reconnect.
- **Request is not rewritten:** check HTTPS decryption, HTTP/2 handling, System-keychain CA trust, the four configured hosts, and the response hook.
- **`patched 0` or stale Maps position:** the payload may be unsupported; regenerate and reload, reconnect, reopen Maps, and allow for caching.
- **Certificate or connectivity errors:** disable the module and HTTPS decryption, reconnect, then review CA trust and routing before retrying.

Run `./macos-shadowrocket/diagnose.sh` for a read-only environment report, or `./macos-shadowrocket/observe-locationd.sh` to watch filtered Core Location logs.

If the problem remains, open a sanitized [Issue](https://github.com/Kuirb/macos-location-spoofer/issues) without CA material, private keys, or sensitive coordinates.

## Restore and uninstall

- Disable/remove the module and HTTPS decryption, then reconnect Shadowrocket.
- Delete your CA from Shadowrocket and the matching certificate from the **System** keychain only after checking that no other decryption rule shares it.
- Remove the local script, private config, generated module, and debug logs; never delete unrelated certificates or `/var/db/locationd`.

## Limitations

- Apple WLoc/ARPC is undocumented and may change without notice.
- Only recognized Wi-Fi and cell records on the configured hosts and exact `/clls/wloc` path are rewritten.
- Caching, pinning, routing bypass, or incompatible payloads can prevent interception.
- Apps may use IP location, account data, Bluetooth, hardware GPS, or their own backend instead.

This is not an anonymity tool or “undetectable”; independent signals can disagree with the rewritten result.

## Tests

Run `./macos-shadowrocket/verify.sh` for dependency-free checks of configuration, module output, protocol rewriting, framing, gzip, and runtime behavior. Tests use synthetic fixtures and cannot prove live CA trust or interception.

## Credits and license

Derived from [mekos2772/ios-location-spoofer](https://github.com/mekos2772/ios-location-spoofer), which credits [acheong08/ios-location-spoofer](https://github.com/acheong08/ios-location-spoofer). See [NOTICE](NOTICE) for the macOS/Shadowrocket modification notice and attribution.

Licensed under [GNU AGPL-3.0](LICENSE) and provided without warranty. Review the license obligations before modifying, running as a network service, or redistributing this project.
