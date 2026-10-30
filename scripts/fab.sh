#!/usr/bin/env bash
# Checks the KiCad design and builds the JLCPCB order files into fab/.
# Runs the same locally and in CI. Override the CLI with KICAD_CLI=/path/to/kicad-cli.
set -euo pipefail

cd "$(dirname "$0")/.."
KICAD_CLI="${KICAD_CLI:-kicad-cli}"
SCH="hardware/Smart USB Relay.kicad_sch"
PCB="hardware/Smart USB Relay.kicad_pcb"
OUT="fab"
NAME="smart-usb-relay"

mkdir -p "$OUT/gerbers"

echo "== ERC"
"$KICAD_CLI" sch erc --severity-error --exit-code-violations -o "$OUT/erc.rpt" "$SCH"

echo "== DRC (with schematic parity)"
"$KICAD_CLI" pcb drc --schematic-parity --severity-error --exit-code-violations -o "$OUT/drc.rpt" "$PCB"

echo "== Gerbers + drill"
"$KICAD_CLI" pcb export gerbers -o "$OUT/gerbers/" \
  --layers "F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts" "$PCB"
"$KICAD_CLI" pcb export drill -o "$OUT/gerbers/" --format excellon --excellon-units mm \
  --excellon-separate-th "$PCB"
(cd "$OUT/gerbers" && python3 -m zipfile -c "../$NAME-gerbers.zip" ./*)

echo "== BOM (JLC format)"
"$KICAD_CLI" sch export bom -o "$OUT/$NAME-bom.csv" \
  --fields 'Value,Reference,${FOOTPRINT_NAME},LCSC' \
  --labels 'Comment,Designator,Footprint,LCSC' \
  --group-by 'Value,LCSC,${FOOTPRINT_NAME}' \
  --ref-delimiter ',' --ref-range-delimiter '' "$SCH"

echo "== CPL (JLC format)"
"$KICAD_CLI" pcb export pos -o "$OUT/pos.csv" --format csv --units mm --side front "$PCB"
python3 - "$OUT/pos.csv" "$OUT/$NAME-bom.csv" "$OUT/$NAME-cpl.csv" <<'EOF'
import csv, math, sys

pos_path, bom_path, cpl_path = sys.argv[1:]
# JLC places its own (LCSC/EasyEDA) model on its own origin. Where our KiCad footprint's
# origin differs, shift the placement: offset in the footprint's local axes (mm, KiCad
# y-down) from our origin to JLC's.
ORIGIN_OFFSETS = {
    # HRO TYPE-C-31-M-17 (C283540): LCSC origin is 1.25 mm towards the back of the
    # connector (shell holes at y -3.0/0.8 in KiCad vs -1.75/2.05 in LCSC).
    "USB_C_Receptacle_HRO_TYPE-C-31-M-17": (0.0, -1.25),
}
# Only parts JLC places: anything in the BOM (U1, test pads and holes are excluded there).
with open(bom_path, newline="") as f:
    placed = {ref for row in csv.DictReader(f) for ref in row["Designator"].split(",") if ref}
with open(pos_path, newline="") as f, open(cpl_path, "w", newline="") as out:
    w = csv.writer(out)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    rows = [r for r in csv.DictReader(f) if r["Ref"] in placed]
    for r in rows:
        x, y, rot = float(r["PosX"]), float(r["PosY"]), float(r["Rot"])
        dx, dy = ORIGIN_OFFSETS.get(r["Package"], (0.0, 0.0))
        a = math.radians(rot)
        # Rotate into board axes (KiCad, y-down), then flip y for the position file (y-up).
        x += dx * math.cos(a) + dy * math.sin(a)
        y -= -dx * math.sin(a) + dy * math.cos(a)
        w.writerow([r["Ref"], f"{x:.3f}mm", f"{y:.3f}mm",
                    "Top" if r["Side"] == "top" else "Bottom", f"{rot:.1f}"])
missing = placed - {r["Ref"] for r in rows}
if missing:
    sys.exit(f"BOM parts missing from the position file: {sorted(missing)}")
print(f"{len(rows)} placements")
EOF
rm "$OUT/pos.csv"

echo "== Done: $OUT/"
ls -1 "$OUT"
