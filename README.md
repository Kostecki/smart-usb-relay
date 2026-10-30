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

## Order files

CI runs `scripts/fab.sh` on every change to the hardware and uploads `fab/` as a build artifact. Locally:

```sh
KICAD_CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli scripts/fab.sh
```

Upload `fab/smart-usb-relay-gerbers.zip`, then the BOM and CPL for assembly. Leave U1 (SuperMini), the test pads and the mounting holes out of assembly (they're already excluded from the BOM and CPL), and choose "Remove Order Number".
