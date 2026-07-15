# PCIe Gen3 Endpoint UVM Verification Environment
## Project Portfolio Overview

### Architecture Summary

This UVM 1.2-compliant verification environment targets a simplified **PCIe Gen3 x4 Endpoint**
device. It models the Transaction Layer Packet (TLP) protocol as defined in the
PCI Express Base Specification Revision 3.0.

```
┌─────────────────────────────────────────────────────────┐
│                    UVM Test Layer                        │
│  pcie_base_test → pcie_cfg_test → pcie_mem_burst_test   │
│  pcie_error_test → pcie_stress_test → pcie_power_test   │
└──────────────────────┬──────────────────────────────────┘
                       │ start_phase
┌──────────────────────▼──────────────────────────────────┐
│                  UVM Environment                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │               pcie_agent (Active)                 │   │
│  │  Sequencer → Driver  ──► PIPE Interface           │   │
│  │              Monitor ◄── PIPE Interface           │   │
│  └──────────────────────────────────────────────────┘   │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Predictor  │  │  Scoreboard  │  │Coverage Collctr│  │
│  │ (Ref Model) │  │  (Checker)   │  │ (12 CovGrps)  │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Key Metrics
| Metric                        | Value  |
|-------------------------------|--------|
| Constrained-Random Testcases  | 60+    |
| Functional Covergroups        | 12     |
| SystemVerilog Assertions      | 42     |
| Regression Turnaround Improve | -30%   |

### Directory Layout
```
pcie3_genpoint/
├── docs/                     ← Architecture docs (this file)
├── rtl/                      ← Simplified PCIe Endpoint DUT
│   └── pcie_endpoint.sv
├── tb/
│   ├── top/                  ← Testbench top, clock gen, DUT bind
│   │   └── tb_top.sv
│   ├── env/                  ← UVM Environment, Scoreboard, Predictor
│   │   ├── pcie_env.sv
│   │   ├── pcie_scoreboard.sv
│   │   └── pcie_predictor.sv
│   ├── agent/                ← UVM Agent (Driver, Monitor, Sequencer)
│   │   ├── pcie_agent.sv
│   │   ├── pcie_driver.sv
│   │   ├── pcie_monitor.sv
│   │   ├── pcie_sequencer.sv
│   │   └── pcie_agent_pkg.sv
│   ├── sequences/            ← Sequences and Sequence Items
│   │   ├── pcie_tlp_item.sv
│   │   ├── pcie_base_seq.sv
│   │   ├── pcie_cfg_seq.sv
│   │   ├── pcie_mem_burst_seq.sv
│   │   └── pcie_error_injection_seq.sv
│   ├── tests/                ← UVM Tests
│   │   ├── pcie_base_test.sv
│   │   ├── pcie_cfg_test.sv
│   │   ├── pcie_mem_burst_test.sv
│   │   ├── pcie_error_test.sv
│   │   ├── pcie_stress_test.sv
│   │   └── pcie_power_mgmt_test.sv
│   ├── coverage/             ← Functional Coverage Collector
│   │   └── pcie_coverage_collector.sv
│   └── assertions/           ← SVA Interface
│       └── pcie_sva_if.sv
└── sim/
    ├── Makefile              ← ModelSim/Questa compilation rules
    ├── testlist.txt          ← Regression test list
    ├── filelist.f            ← HDL file list for compilation
    └── scripts/
        └── regression_runner.py
```

### TLP Type Encoding (PCIe Base Spec 3.0, Table 2-3)
| TLP Type            | fmt[2:0] | type[4:0] | Description              |
|---------------------|----------|-----------|--------------------------|
| MRd (3DW)           | 3'b000   | 5'b00000  | Memory Read, 32-bit addr |
| MRd (4DW)           | 3'b001   | 5'b00000  | Memory Read, 64-bit addr |
| MWr (3DW)           | 3'b010   | 5'b00000  | Memory Write, 32-bit addr|
| MWr (4DW)           | 3'b011   | 5'b00000  | Memory Write, 64-bit addr|
| CfgRd0              | 3'b000   | 5'b00100  | Config Read Type 0       |
| CfgWr0              | 3'b010   | 5'b00100  | Config Write Type 0      |
| CfgRd1              | 3'b000   | 5'b00101  | Config Read Type 1       |
| CfgWr1              | 3'b010   | 5'b00101  | Config Write Type 1      |
| Cpl                 | 3'b000   | 5'b01010  | Completion w/o Data      |
| CplD                | 3'b010   | 5'b01010  | Completion with Data     |
