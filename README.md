# Smart USB Relay

An inline USB-C box that switches and meters 5 V power to a USB gadget (lamp, fan, sensor) from Home Assistant. Charger → box → device.

- ESP32-H2 SuperMini running ESPHome over Thread (OTA, no Wi-Fi)
- TPS2557 current-limited switch (3 A), INA226 voltage/current/power metering → kWh in the Energy dashboard
- USB-C in and out: fixed 5 V sink towards the charger, 1.5 A / 3 A source towards the device (follows what the charger offers)
- 60 × 30 mm, 2 layers, assembled by JLCPCB (except the SuperMini, which sits on headers)

The full design, every decision behind it, and the pre-order checklist are in [SPEC.md](SPEC.md).

## Layout

| Path | What |
|---|---|
| `hardware/` | KiCad 10 project, project symbol/footprint libraries, footprints converted from LCSC (`lcsc/`) |
| `firmware/` | ESPHome configuration |
| `scripts/fab.sh` | ERC + DRC (with schematic parity), then Gerbers, drill, BOM and CPL for JLCPCB into `fab/` |

## Firmware

The config lives in the Home Assistant ESPHome dashboard (ESPHome 2026.10.0 or newer) and is edited there. `firmware/smart-usb-relay.yaml` is a copy, updated by hand when the behaviour changes.

1. In the dashboard's **Secrets**, add `thread_tlv` and `api_encryption_key` (`openssl rand -base64 32`; it also encrypts OTA). `firmware/secrets.example.yaml` explains how to get the Thread TLV with an Apple border router: send the credentials from the iPhone companion app, then read them with `thread/get_dataset_tlv` in the browser console.
2. Create a new device, skip the Wi-Fi questions, and replace its YAML with `firmware/smart-usb-relay.yaml`. For a second box, change `name` and `friendly_name` under `substitutions`.
3. Flash the SuperMini over its own USB-C **before** fitting it to the board: **Install → Plug into this computer** (Chrome or Edge). If the port doesn't show up, hold BOOT while plugging it in.
4. It joins your Thread network as a router and Home Assistant discovers it. Later updates: **Install → Wirelessly**.

Before it's on the board, the ADC pins float, so "Device attached" and the charger readings are meaningless.

Entities: Output, Device attached, Output powered, Overcurrent tripped, Voltage, Current, Power, Energy, Charger voltage, Charger advertised current, Advertised to device; config: Power-on behavior, Force output, Current limit.

## Order files

CI runs `scripts/fab.sh` on every change to the hardware and uploads `fab/` as a build artifact. Locally:

```sh
KICAD_CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli scripts/fab.sh
```

Upload `fab/smart-usb-relay-gerbers.zip`, then the BOM and CPL for assembly. Leave U1 (SuperMini), the test pads and the mounting holes out of assembly (they're already excluded from the BOM and CPL), and choose "Remove Order Number".
