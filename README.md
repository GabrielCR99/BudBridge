# MeloBuds Control

A native macOS app for the **QCY MeloBuds Pro**. It covers the official QCY phone app's earbud
settings plus the Mac's own Bluetooth audio connection.

- **Audio link** (Classic Bluetooth, IOBluetooth): connect or disconnect the earbuds from this Mac.
- **Control link** (Bluetooth LE, CoreBluetooth): battery, noise control (ANC scenes and strength,
  transparency, vocal), EQ presets and a 10-band custom EQ, channel balance, touch controls,
  LDAC, dual device connection, gaming mode, wear detection, sleep mode, prompt volume and language,
  auto power-off, rename, reset and factory reset.
- **Find earbuds**: plays a loud chirp through the current output, which is what the phone app does too.
- Menu-bar extra with battery, noise mode and gaming mode.

> **New to the code?** Open [`docs/melobuds-control.html`](docs/melobuds-control.html) in a browser: an interactive walkthrough of the protocol and the Swift code, with Dart/Flutter comparisons.

Requires macOS 26+ and Swift 6.2+. Built with Swift 6 language mode, main-actor default
isolation, `@Observable`, isolated protocol conformances, typed throws and Swift Testing.

## Build

```sh
./scripts/build-app.sh          # → build/MeloBuds Control.app (ad-hoc signed)
open "build/MeloBuds Control.app"
swift test                      # protocol tests against bytes captured from real earbuds
swift scripts/make-icon.swift   # regenerate Resources/AppIcon.icns (vector-drawn, no assets)
```

The first time it launches, macOS asks for Bluetooth access. To use the earbuds for audio, pair them once in
System Settings › Bluetooth.

## Notes and limits

- **One controller at a time.** The earbuds accept a single LE control connection. While the QCY app
  on the phone holds it, the Mac can't connect. Use **Release to Phone** and **Take Control** to hand it over.
- **LDAC**: macOS has no LDAC encoder, so the Mac always streams AAC or SBC. The switch changes the
  earbuds' setting for Android sources.
- **LDAC and dual device connection are mutually exclusive.** Changing either one restarts the earbuds,
  and the app reconnects by itself. Turn on dual device connection to keep your phone and the Mac connected together.

## Protocol (reverse-engineered from `com.qcymall.googleearphonesetup` 4.0.7)

GATT service `A001` on the earbuds' LE identity ("QCY MeloBuds Pro-APP", classic MAC + 1):

| Char | Props | Use |
|------|-------|-----|
| `1001` | write w/o resp | command frames |
| `1002` | read, notify | setting frames; reading it returns every setting |
| `0007` | read | firmware `L.L.L R.R.R` |
| `0008` | read, notify | battery `[L, R, case]`, bit 7 = charging |
| `000B` | read, write | legacy EQ slot |
| `000D` | read, write | touch controls, `[gesture, action]` pairs |

Frame: `FF <len> { <cmd> <n> <payload> }*`. Request a value with `FE 01 <cmd>`. Boolean switches
are written as `1` = on, `2` = off and read back as `1` and `0`.

| Cmd | Setting | Payload |
|-----|---------|---------|
| `09` | Gaming mode | bool |
| `10` | Sleep mode | bool |
| `16` | Balance | 0–100 (50 = center) |
| `17` | Noise control | `[mode, scene, level]`: `02 00 00` off · `01 01‑03 00‑02` Indoor/Commuting/Noisy · `01 04 00` anti-wind · `01 05 00` adaptive · `03 01 01‑06` transparency · `03 02 00` vocal |
| `18` | Name | UTF-8 |
| `19` | Prompt language | ASCII `WQ00` English, `WQ01` Chinese |
| `1D` | Prompt volume | 4 / 6 / 8 / 10 |
| `1F` | Power off after disconnect | u16 LE minutes, `FFFF` = never |
| `22` | Equalizer | `[id, masterGain s16] + 20 × [freq u16, gain×100 s16, Q×100 u16, type]` (type `04` shelf, `00` peak, `FF` user band) |
| `23` | LDAC | bool |
| `24` | Dual device | bool |
| `2C` | Wear detection | `[enabled, music 0‑3, ANC follows wear]` |
| `01` / `03` | Reset settings / factory reset | none |

EQ presets and option labels come from the model's control panel
(`api.watch.qcy.com/product/findControlPanels`, `modelId=19786` = advertised vendor ID `0x4D4A`).
