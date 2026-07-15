# filelist.f — HDL source file list for ModelSim/Questa compilation
# Usage: vlog -f filelist.f
# Order: packages → interfaces → RTL → TB components → top

# ── UVM Library ───────────────────────────────────────────────────────────────
+incdir+$UVM_HOME/src
$UVM_HOME/src/uvm_pkg.sv

# ── PCIe TLP Types Package ────────────────────────────────────────────────────
../tb/sequences/pcie_tlp_item.sv

# ── Interfaces ────────────────────────────────────────────────────────────────
../tb/top/pcie_pipe_if.sv
../tb/assertions/pcie_sva_if.sv

# ── RTL DUT ───────────────────────────────────────────────────────────────────
../rtl/pcie_endpoint.sv

# ── Agent Layer ───────────────────────────────────────────────────────────────
../tb/agent/pcie_sequencer.sv
../tb/agent/pcie_driver.sv
../tb/agent/pcie_monitor.sv
../tb/agent/pcie_agent.sv

# ── Coverage ──────────────────────────────────────────────────────────────────
../tb/coverage/pcie_coverage_collector.sv

# ── Environment Layer ─────────────────────────────────────────────────────────
../tb/env/pcie_predictor.sv
../tb/env/pcie_scoreboard.sv
../tb/env/pcie_env.sv

# ── Sequences ─────────────────────────────────────────────────────────────────
../tb/sequences/pcie_base_seq.sv
../tb/sequences/pcie_cfg_seq.sv
../tb/sequences/pcie_mem_burst_seq.sv
../tb/sequences/pcie_error_injection_seq.sv

# ── Tests ─────────────────────────────────────────────────────────────────────
../tb/tests/pcie_base_test.sv
../tb/tests/pcie_cfg_test.sv
../tb/tests/pcie_mem_burst_test.sv
../tb/tests/pcie_error_test.sv
../tb/tests/pcie_stress_test.sv
../tb/tests/pcie_power_mgmt_test.sv

# ── Testbench Top ─────────────────────────────────────────────────────────────
../tb/top/tb_top.sv
