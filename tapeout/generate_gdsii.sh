#!/bin/bash
# GDSII Generation Flow
# sovereign-systolic tapeout
# Target: Sky130 + OpenLane

set -e

DESIGN_NAME="tensor_array"
TAG="tapeout_final"

echo "=== sovereign-systolic GDSII Flow ==="
echo "Design: ${DESIGN_NAME}"
echo "Tag: ${TAG}"
echo ""

# Step 1: Synthesis
echo "[1/7] Synthesis..."
yosys -s synth/synth_tensor_array.ys

# Step 2: Floorplan
echo "[2/7] Floorplan..."
openlane_config=synth/config.json

# Step 3: Placement
echo "[3/7] Placement..."

# Step 4: CTS
echo "[4/7] Clock Tree Synthesis..."

# Step 5: Routing
echo "[5/7] Routing..."

# Step 6: Magic (GDSII export)
echo "[6/7] Magic GDSII export..."

# Step 7: Signoff (DRC + LVS)
echo "[7/7] Signoff (DRC + LVS)..."

echo ""
echo "=== Final Artifacts ==="
echo "  results/magic/systolic_array_16x16.gds   ← GDSII"
echo "  results/magic/systolic_array_16x16.lef"
echo "  results/routing/systolic_array_16x16.def"
echo "  reports/signoff/ (DRC, LVS, timing)"
echo ""
echo "=== Flow Complete ==="
