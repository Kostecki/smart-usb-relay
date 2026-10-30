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
import csv, sys

pos_path, bom_path, cpl_path = sys.argv[1:]
# Only parts JLC places: anything in the BOM (U1, test pads and holes are excluded there).
with open(bom_path, newline="") as f:
    placed = {ref for row in csv.DictReader(f) for ref in row["Designator"].split(",") if ref}
with open(pos_path, newline="") as f, open(cpl_path, "w", newline="") as out:
    w = csv.writer(out)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    rows = [r for r in csv.DictReader(f) if r["Ref"] in placed]
    for r in rows:
        w.writerow([r["Ref"], f'{float(r["PosX"]):.3f}mm', f'{float(r["PosY"]):.3f}mm',
                    "Top" if r["Side"] == "top" else "Bottom", f'{float(r["Rot"]):.1f}'])
missing = placed - {r["Ref"] for r in rows}
if missing:
    sys.exit(f"BOM parts missing from the position file: {sorted(missing)}")
print(f"{len(rows)} placements")
EOF
rm "$OUT/pos.csv"

echo "== Done: $OUT/"
ls -1 "$OUT"
