# Makefile — PCIe Gen3 UVM simulation
# Questa Sim 2021.4 @ /package/eda/mg/questa2021.4/questasim

SHELL      := /bin/bash
QUESTA     := /package/eda/mg/questa2021.4/questasim
UVM_HOME   := $(QUESTA)/verilog_src/uvm-1.2
VSIM       := $(QUESTA)/bin/vsim
VLOG       := $(QUESTA)/bin/vlog
VLIB       := $(QUESTA)/bin/vlib
VCOVER     := $(QUESTA)/bin/vcover

WORK      := work
LOG_DIR   := logs
COV_DIR   := coverage

TEST      ?= pcie_base_test
SEED      ?= 1
VERBOSITY ?= UVM_MEDIUM
TIMEOUT   ?= 500ms
JOBS      ?= 4

VLOG_FLAGS := -sv -mfcu -timescale 1ns/1ps         \
              +incdir+$(UVM_HOME)/src               \
              $(UVM_HOME)/src/uvm_pkg.sv            \
              -suppress 2583

VSIM_FLAGS := -batch                                \
              +UVM_TESTNAME=$(TEST)                 \
              +UVM_VERBOSITY=$(VERBOSITY)            \
              -sv_seed $(SEED)                       \
              -coverage                             \
              -do "run $(TIMEOUT); \
                   coverage save $(COV_DIR)/$(TEST)_s$(SEED).ucdb; \
                   quit -f"

.PHONY: all compile sim regr cov_report clean help

all: compile

compile:
	$(VLIB) $(WORK)
	$(VLOG) $(VLOG_FLAGS) -f filelist.f -l compile.log
	@echo "[OK] Compilation done — check compile.log for warnings"

# make sim TEST=pcie_cfg_test SEED=42
sim: | $(LOG_DIR) $(COV_DIR)
	$(VSIM) $(VSIM_FLAGS) $(WORK).tb_top \
		-l $(LOG_DIR)/$(TEST)_s$(SEED).log

# make regr JOBS=8
regr: | $(LOG_DIR) $(COV_DIR)
	python3 scripts/regression_runner.py --testlist testlist.txt --jobs $(JOBS)

cov_report:
	$(VCOVER) merge $(COV_DIR)/merged.ucdb $(COV_DIR)/*.ucdb
	$(VCOVER) report -details -html -output $(COV_DIR)/html_report $(COV_DIR)/merged.ucdb
	@echo "[OK] HTML report: $(COV_DIR)/html_report/index.html"

$(LOG_DIR) $(COV_DIR):
	mkdir -p $@

clean:
	rm -rf $(WORK) $(LOG_DIR) $(COV_DIR) compile.log transcript *.vcd

help:
	@printf "\n  Targets\n"
	@printf "    compile         compile all sources\n"
	@printf "    sim             single test  (TEST=name SEED=N)\n"
	@printf "    regr [JOBS=N]   parallel regression\n"
	@printf "    cov_report      merge UCDBs + HTML coverage report\n"
	@printf "    clean           wipe all generated files\n"
	@printf "\n  Questa: $(QUESTA)\n"
	@printf "  UVM:    $(UVM_HOME)\n\n"
