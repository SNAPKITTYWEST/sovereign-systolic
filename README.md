# sovereign-systolic

Sovereign 16×16 systolic array with 4-bit tensor ISA, microcode controller, WS/OS/IS dataflows, Tensor-Core mode, and path to GDSII.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    sovereign-systolic                         │
├─────────────────────────────────────────────────────────────┤
│  rtl/                                                       │
│    tensor_pkg.sv                 Package (dataflow_t, ops)  │
│    systolic_pe.sv                Processing Element          │
│    array_controller.sv           Microcode-driven FSM        │
│    tensor_core_fp16.sv           FP16 Tensor Core unit       │
│    systolic_array_16x16.sv       16×16 array wrapper         │
│    systolic_array_with_tensor_core.sv  TC integration        │
│  microcode/                                                 │
│    isa_microcode_base.txt        Base ISA (0000-0200)        │
│    systolic_microcode.txt        Systolic-specialized        │
│    extended_ws_os_tc.txt         WS/OS/TC sequences          │
│  tb/                                                        │
│    tb_systolic_array.sv          Testbench                   │
│  synth/                                                     │
│    synth_tensor_array.ys         Yosys synthesis script       │
│    config.json                   OpenLane/OpenROAD config    │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **16×16 PE grid** (256 PEs)
- **4-bit Tensor ISA** — 16 opcodes: NOP, LOAD, STORE, ADD, MUL, MMA, MAX, EXP, SCALE, REDUCE, SHFL, MOV, CMP, BR, SYNC, HALT
- **8-bit control word** per PE: `load_wgt_reg | load_act_reg | acc_en | psum_sel | sparse_en | pass_through | clear_acc | output_en`
- **3 dataflows**: Weight-Stationary (WS), Output-Stationary (OS), Input-Stationary (IS)
- **Tensor-Core mode**: whole array as one m16n8k16 MMA unit
- **Structured sparsity**: 2:4 / 4:8 via `sparse_mask`
- **Microcode ROM** — 512+ entries, drives PE control via FSM
- **FP16 multiply + FP32 accumulate** (placeholder for synthesis)

## PE Micro-Architecture

```
Inputs:
  act_in[15:0]    activation from left/west feeder
  wgt_in[15:0]    weight from top/north feeder
  psum_in[31:0]   partial sum from neighbor
  ctrl[7:0]       micro-control word

Registers:
  wgt_reg[15:0]   stationary weight (WS mode)
  act_reg[15:0]   stationary activation (IS mode)
  acc[31:0]       accumulator (OS mode)
  sparse_mask[3:0] for structured sparsity

Datapath:
  mul = act * wgt
  add = mul + (psum_in or acc)
  out = gated by sparse_mask
```

## Dataflow Selection

| Dataflow | load_wgt_reg | load_act_reg | psum_sel | Notes |
|----------|--------------|--------------|----------|-------|
| WS | 1 (once) | 0 (stream) | 0 | Weights stay, activations flow |
| OS | 0 (stream) | 0 (stream) | 1 | Partial sums stay in accumulator |
| IS | 0 (stream) | 1 (once) | 0 | Activations stay, weights flow |
| TC | 0 (stream) | 0 (stream) | 1 | Whole array = one big MMA |

## Build

### Simulation (Icarus Verilog / Verilator)

```bash
iverilog -g2012 -o tb_systolic rtl/*.sv tb/tb_systolic_array.sv
vvp tb_systolic
```

### Synthesis (Yosys)

```bash
cd synth
yosys -s synth_tensor_array.ys
```

### Physical Design (OpenLane)

```bash
cd synth
openlane config.json
```

## Physical Characteristics (estimated, 7nm class)

| Metric | Value |
|--------|-------|
| PE area | 800–1500 µm² |
| Array + controller | 0.3–0.6 mm² |
| Power (dense FP16) | 0.8–1.5 W @ 1 GHz |
| Clock target | 800 MHz – 1.2 GHz |

## Performance Comparison

| Architecture | Peak (dense) | TOPS/W | Notes |
|---|---|---|---|
| NVIDIA B200 | ~4.5 PFLOPS FP8 | 1.5–2.0 | Software ecosystem |
| Google TPU v5p | ~900+ TFLOPS | 2.5–4.0 | Cloud-only |
| Cerebras WSE-3 | 100+ PFLOPS | High | On-wafer SRAM |
| **sovereign-systolic** | **~0.5–1 TOPS** | **5–10+** | **Matches 4-bit ISA** |

## Next Steps

- Replace integer multiply with FP16/BF16/FP8 IP for synthesis
- Expand microcode ROM with full binary dump
- Larger array (32×32, 64×64) for production TOPS
- Memory controller + HBM interface
- GDSII via OpenROAD

## License

Sovereign Source License v1.0 + BSL-1.1 + AGPL-3.0 (tri-license)

## Author

Ahmad Ali Parr · Bel Esprit D'Accord Irrevocable Trust · EIN 42-697643
Contact: Ahmad <ahmedparr93@gmail.com>
