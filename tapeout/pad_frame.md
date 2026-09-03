# Pad Frame + Bond Pad Placement Description
# sovereign-systolic tapeout

Die size: 1400 µm × 1400 µm

Pad frame (Sky130 style):
- 4 sides, minimum 80–100 µm pad pitch
- Power/Ground pads every 4–6 signal pads
- Corner pads reserved for power

Recommended pad list:
North : clk, rst_n, start, done, busy + 4× VDD/VSS
East : 16× act_west + 6× VDD/VSS
South : 16× psum_south + 6× VDD/VSS
West : 16× wgt_north + 6× VDD/VSS

Total pads ≈ 70–80 (comfortable for QFN-88 or BGA-100)

Bond pad placement rules:
- Signal pads centered on each side
- Power pads interleaved
- Keep-out region 30 µm from die edge
- ESD protection diodes on all I/Os
