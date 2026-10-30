# Smart USB Relay v1.0 — spec

Inline USB-C box: charger → box → device. Switches and meters 5 V power to a USB gadget, controlled from Home Assistant via ESPHome over Thread.

## Electrical

- 5 V only, power only: no USB PD, no Quick Charge, D+/D− not connected. 3 A continuous design target.
- **Input (J1)**: 6-pin top-mount USB-C receptacle with THT shell legs.
  - 5.1 kΩ Rd on CC1/CC2 (always a 5 V sink).
  - TVS on VBUS_IN; ESD array on CC1/CC2.
  - 5 A fast-acting 1206 fuse; 10 µF input bulk cap.
  - CC1/CC2 → 1 kΩ → ADC (charger's advertised current: Default / 1.5 A / 3 A).
  - 100k/100k divider + 100 nF → ADC (charger voltage).
- **Switch**: current-limited USB load switch IC, ~20–30 mΩ, limit ~3.3–3.5 A, soft start, thermal shutdown, open-drain FAULT. EN pulled down (off while the ESP boots). Exact part chosen from JLC stock.
- **Metering**: INA226 (I2C 0x40), 10 mΩ 1 % shunt (2010/2512), Kelvin traces. Measures the output side only.
- **Output (J2)**: same connector as J1.
  - 12 kΩ Rp to 3V3 on CC1/CC2 (1.5 A). Q2 (P-FET) adds a parallel Rp for 3 A, enabled only when the charger advertises 3 A. Q2 gate pulled up (off by default).
  - CC1/CC2 → 1 kΩ → ADC (attach detection).
  - ESD array on CC1/CC2; 1 µF output cap; bleed resistor to 0 V when off.
- **Controller (U1)**: ESP32-H2 SuperMini on 2×9 header pins or female headers (hand-soldered, not JLC-assembled). Raising it lets a USB-C plug reach its port for lid-off reflashing (and with female headers the module simply pulls out), and lets low parts sit underneath. Footprint assumes **15.24 mm row spacing — measure the real module before ordering**.
  - 5V pin fed from VBUS_IN through a Schottky diode (blocks backfeed from the SuperMini's own USB).
  - Its 3V3 pin supplies the rest of the board.
  - Antenna (opposite end from its USB-C) at a board edge with a copper keepout on both layers.

### U1 pin map

Only the two edge rows are used; the interior pads (GPIO22, 25, 26, 27) and B+/B− are not.

| GPIO | Signal | Notes |
|---|---|---|
| 1 | CC1_IN sense | ADC1_CH0 |
| 2 | CC2_IN sense | ADC1_CH1 |
| 3 | CC1_OUT sense | ADC1_CH2 |
| 4 | CC2_OUT sense | ADC1_CH3 |
| 5 | VIN sense | ADC1_CH4 |
| 0 | FAULT (load switch FAULT + INA226 ALERT, wired-OR) | 10 kΩ pull-up |
| 10 | EN_OUT | 100 kΩ pull-down |
| 11 | RP3A_EN (Q2 gate, active low) | 100 kΩ pull-up |
| 12 | I2C SDA | 4.7 kΩ pull-up |
| 14 | I2C SCL | 4.7 kΩ pull-up |
| 13 | onboard blue LED | optional internal status LED only |
| 8, 9, 23, 24 | unused | 8 = strapping + onboard WS2812; 9 = strapping + BOOT button; 23/24 = UART0 (ROM boot log) |

- GPIO1–5 are the H2's only ADC pins. Datasheet v1.3 lists only GPIO8, 9 and 25 as strapping pins, so CC lines on GPIO2/3 are safe (ESP-IDF's GPIO page also lists 2/3, but the datasheet's boot-configuration section doesn't).
- ADC at 12 dB attenuation measures 0–3.3 V (±23 mV calibrated). Every sensed node stays within that: VIN/2 ≤ 2.75 V, CC_IN ≤ 2.04 V, CC_OUT ≤ 3.3 V (open, pulled up by Rp).
- GPIO13/14 double as the 32 kHz crystal pins; the SuperMini fits no crystal, so they're plain GPIO.

### Parts (JLC)

| Ref | Part | LCSC | Notes |
|---|---|---|---|
| J1, J2 | HRO TYPE-C-31-M-17 | C283540 | 5 A, 6-pin; KiCad stock footprint (LCSC one has non-USB pad names) |
| U2 | TPS2557DRBR | C130056 | R8 = 33 kΩ → limit 3.03 A min / ~3.35 A typ / 3.6 A max; FAULT deglitch 6–13 ms |
| U3 | INA226AIDGSR | C49851 | A0/A1 = GND → 0x40 |
| RS1 | Vishay WSLP2512R0100FEA, 10 mΩ 1 % | C241862 | |
| F1 | JFC1206-1500FS, 5 A fast | C136351 | |
| D1 | SMF6.0A (unidirectional) | C19077499 | JLC Preferred (no setup fee) |
| D2, D4 | SRV05-4 | C13612 | D2 VP → VBUS_IN; **D4 VP → +3V3** (on VBUS_OUT it would back-feed the off output to ~2.7 V through Rp) |
| D3 | B5819W | C8598 | Basic |
| Q1 | AO3401A | C15127 | Basic; 3 A Rp switch |
| C1, C5 | 10 µF 25 V 0805 | C15850 | C5 (output) raised from 1 µF |
| R12 | 10 kΩ | C25804 | Output bleed (0.5 mA when on; subtract in firmware if it matters) |

Library approach: KiCad symbols (typed pins, so ERC is meaningful) + LCSC/EasyEDA footprints (JLC rotation/origin) for every JLC-placed non-passive, in `lcsc/LCSC.pretty`. Passives use KiCad's standard footprints. TPS2557 symbol and SuperMini symbol/footprint are in `Smart_USB_Relay.*`; the TPS2557 footprint has 6 thermal vias added.

## Behaviour (ESPHome over Thread)

- OpenThread FTD (router), native API, OTA over Thread. Thread dataset compiled in; a new Thread network means a USB reflash with the lid off.
- Output is powered only when **enabled** and a **device is attached** (CC_OUT ≈ 1 V), unless **Force output** is on. Ignore Ra (e-marked cable) levels. Unplug → VBUS off within 650 ms.
- Downstream advertisement: 3 A only when CC_IN reads 3 A, otherwise 1.5 A.
- Overcurrent (hardware FAULT, or software limit, default 3.0 A, configurable) **latches off** and sets *Overcurrent tripped*; cleared by the next manual turn-on.
- Power-on behavior: Off / On / Previous, default **Off**.

### Home Assistant entities

- Switch: Output (requested state)
- Binary sensors: Device attached, Output powered, Overcurrent tripped
- Sensors: Voltage, Current, Power, Energy (kWh, total_increasing), Charger voltage, Charger advertised current, Advertised to device
- Config: Power-on behavior (select), Force output (switch), Current limit (number)

## PCB

- 2 layers, 1 oz, 60 × 30 mm, 1.5 mm corner radius. J1/J2 on the short ends, overhanging 0.5 mm. SuperMini antenna end at the top edge; antenna keepout (no copper or parts, both layers) to the edge.
- Parts under the module must stay below ~1.5 mm if it's mounted on plain header pins (all current parts are ≤ 1.2 mm).
- 3 A path hand-routed on top, 1.2–1.5 mm wide, never changing layer: J1 → F1 → VBUS_IN bus along the bottom edge → U2 → RS1 → vertical bus → J2. Kelvin pair from RS1 to U3 (VIN− hops under VIN+ on the bottom layer through two vias).
- Signals autorouted with Freerouting 2.5.0 (Ground class excluded). GND pours on both layers with stitching vias; GND pads of D2, D4, U2, U3 solid-connected.
- DRC: 0 errors, 0 unconnected, 0 schematic-parity issues. 8 silkscreen warnings remain from KiCad's stock HRO connector outline crossing the board edge (JLC clips them).
- 4 × M2 mounting holes (2.2 mm drill) on GND, clear of the antenna keepout.
- Test pads (not assembled): VBUS_IN, VBUS_OUT, 3V3, GND.
- No buttons or LEDs exposed. Silkscreen (top side): `IN →`, `→ OUT`, `Smart USB Relay v1.0`. No date. Order with "Remove Order Number".

## Deliverables

- KiCad schematic + PCB, ERC/DRC clean.
- LCSC part numbers on every assembled part; JLC BOM + CPL with U1 and test pads excluded.
- Gerbers + drill files.
- ESPHome YAML.
- Not ordered by Claude.

## Before ordering

- **Measure the SuperMini's row spacing** (pin centre to pin centre) and fix `ESP32-H2_SuperMini_Header` if it isn't 15.24 mm; also confirm the antenna sits at the end opposite the USB port.
- Check JLC's assembly preview for orientation of the load switch, Q2, U3, ESD arrays, J1/J2.
