# Earbud protocol

How the app talks to Nothing and CMF earbuds. Everything here is implemented in
`Sources/NothingKit`. The protocol was reverse engineered by
[ear-web](https://github.com/radiance-project/ear-web). The serial number and
ear tip test ids come from
[nikiomori/nothing-x-macos](https://github.com/nikiomori/nothing-x-macos).

## Transport

- Bluetooth Classic, Serial Port Profile over **RFCOMM**.
- Service UUID `aeac4a03-dff5-498f-843a-34487cf133eb`. The RFCOMM channel id
  comes from the device's SDP record.
- The buds must be paired and connected (for audio) in macOS first. The app
  only opens the control channel on top of that.
- Only one controller at a time: if the phone app is connected, the channel won't open.

## Frame format

| Bytes | Field |
| --- | --- |
| 0 | `0x55` start byte |
| 1–2 | flags, `0x60 0x01` when sending |
| 3–4 | command, little-endian `u16` |
| 5 | payload length |
| 6 | reserved |
| 7 | operation id (incrementing counter) |
| 8… | payload |
| last 2 | CRC-16/MODBUS over everything before it, little-endian |

Incoming data is a byte stream: one read can hold several frames or part of
one. `FrameParser` buffers, resyncs on `0x55` and splits by the length byte.

## Commands

Commands starting with `0xC0` read a value and `0xF0` write one. Replies come
back as `0x40xx`. Unsolicited updates arrive as `0xE0xx` or `0x60xx`.

| Feature | Read | Write | Reply / update | Payload |
| --- | --- | --- | --- | --- |
| Battery | `C007` | — | `4007`, `E001` | `[count, (part, level\|0x80 charging)…]`. Parts: 2 left, 3 right, 4 case, 6 single unit |
| Noise control | `C01E` | `F00F` | `401E`, `E003`, `6003` | write `[1, code, 0]`; codes: 1 ANC high, 2 mid, 3 low, 4 adaptive, 5 off, 7 transparency |
| Bass Enhance | `C04E` | `F051` | `404E` | `[enabled, level×2]` (5-level) or `[enabled, 0/5/10]` (3-step) |
| In-ear detection | `C00E` | `F004` | `400E` | write `[1, 1, on]` |
| Low latency | `C041` | `F040` | `4041` | `[1 on / 2 off, 0]` |
| Firmware | `C042` | — | `4042` | ASCII, e.g. `1.0.3.124` |
| Serial number | `C006` | — | `4006` | text lines `device,type,value`; type 4 = serial |
| EQ preset (Nothing) | `C01F` | `F010` | `401F` | `[presetId, 0]` |
| EQ preset (CMF) | `C050` | `F01D` | `4050` | `[presetId, 0]` |
| Custom EQ | `C044` | `F041` | `4044` | see below |
| Spatial audio | `C04F` | `F052` | `404F` | `[mode, headTracking]` |
| Personal Sound (Mimi) | `C022` | `F015` | `4022` | `[on]` |
| Personal Sound (Audiodo) | `C05A` | `F05C` | `405A`, `E019`, `6019` | `[on]` |
| Dual connection on/off | `C027` | `F01A` | `4027` | `[on]` |
| Dual connection devices | `C028` | — | `4028` | request `[startIndex]`; reply `[?, ?, count, (flags, mac×6, nameLen, name…)…]` |
| Dual connect / disconnect | — | `F01B` | `E00E` event | `[connect, mac×6]` |
| Gestures | `C018` | `F003` | `4018` | read: `[count, (device, button, type, action)…]`; write `[1, device, button, type, action]` |
| Find Buds | — | `F002` | — | buds `[2 left / 3 right, on]`, headphones `[6, on]`, Ear (1) `[on]` |
| Ear tip fit test | — | `F014` | `E00D` / `600D` | start `[1]`; result `[left, right]`: 0 good, 1 poor, other = not in ear |

### Custom EQ payload

Three biquad filters as little-endian `f32`s:

```
[count=3] [totalGain f32]
  [type u8][gain f32][freq f32][q f32]   × 3
  [0 0 0]                                × 3
```

| Band | Filter type | Frequency | Q |
| --- | --- | --- | --- |
| Mid | 1 peak | 980 Hz | 0.7 |
| Treble | 2 high shelf | 3400 / 3500 / 6900 Hz (per model) | 1.0 |
| Bass | 0 low shelf | 140 Hz | 0.8 |

Gains are −6…+6 dB. `totalGain` is minus the largest boost, so the output
doesn't clip.

### Gesture codes (CMF tap layout)

Devices: 2 left, 3 right. Gesture types: 2 double tap, 3 triple tap, 7 tap and
hold, 9 double tap and hold.

| Action | Code |
| --- | --- |
| Off | 1 |
| Play/Pause | 2 |
| Skip back / forward | 8 / 9 |
| Voice assistant | 11 |
| Volume up / down | 18 / 19 |
| Noise control cycle: ANC+Transparency+Off | 10 |
| … Transparency+Off | 20 |
| … ANC+Off | 21 |
| … ANC+Transparency | 22 |

### Spatial audio modes

| Mode | Wire `[mode, head]` | Capability bit |
| --- | --- | --- |
| Off | `[0, 0]` | always |
| Head tracked | `[1, 1]` | `0x01` |
| Fixed | `[1, 0]` | `0x02` |
| Concert | `[2, 0]` | `0x08` |
| Theatre | `[3, 0]` | `0x10` |
| Game | `[4, 0]` | `0x20` |

## Debugging

Run with `NXM_DEBUG=1` to log every frame in hex:

```bash
NXM_DEBUG=1 swift run NothingXMac
# [NothingXMac] -> 55600107c0000001acdf      (GET_BATTERY, operation id 1)
# [NothingXMac] <- 5560010740...          (battery reply)
```

To add a model or command, put protocol facts in `NothingKit`, add a check to
`Sources/NothingKitChecks/main.swift`, then handle the reply in
`EarbudsController.handle(_:)`.
