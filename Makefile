# UART + APB IP -- build / run / regress with Verilator (>= 5.0)
#
#   make            build + run the full testbench (seed 1)
#   make lint       strict lint of the RTL only (-Wall)
#   make TEST=rx_errors   run a single test (see names in tb/tb_uart_apb.sv)
#   make regress SEEDS=20 run N random seeds
#   make wave       run with VCD dump -> build_trace/wave.vcd (open in gtkwave)
#   make cov        line/toggle coverage report -> build_cov/annot/
#   make clean

VERILATOR ?= verilator
TOP       ?= tb_uart_apb
TB_FILES  ?= tb/apb_checker.sv tb/uart_sva.sv tb/tb_uart_apb.sv
RTL_FILES := rtl/sync_fifo.sv rtl/uart_baud_gen.sv rtl/uart_tx.sv rtl/uart_rx.sv rtl/uart_apb.sv

BUILD     ?= build
SEED      ?= 1
SEEDS     ?= 5
TEST      ?= all
VEXTRA    ?=
VMAIN     ?= --binary

VFLAGS := $(VMAIN) --timing --assert \
          -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
          --top-module $(TOP) -Mdir $(BUILD) -o sim $(VEXTRA)

SIM := $(BUILD)/sim

.PHONY: all test build lint regress wave cov clean help
all: test

build: $(SIM)
$(SIM): $(RTL_FILES) $(TB_FILES)
	$(VERILATOR) $(VFLAGS) $(RTL_FILES) $(TB_FILES)

test: build
	./$(SIM) +TEST=$(TEST) +verilator+seed+$(SEED) +verilator+rand+reset+2

lint:
	$(VERILATOR) --lint-only -Wall --top-module uart_apb $(RTL_FILES)

regress: build
	@fail=0; \
	for s in $$(seq 1 $(SEEDS)); do \
	  ./$(SIM) +TEST=all +verilator+seed+$$s +verilator+rand+reset+2 > $(BUILD)/regress_$$s.log 2>&1 \
	    && echo "seed $$s: PASS" \
	    || { echo "seed $$s: FAIL  (log: $(BUILD)/regress_$$s.log)"; fail=1; }; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi; \
	echo "regression: all $(SEEDS) seeds passed"

wave:
	$(MAKE) build BUILD=build_trace VEXTRA="--trace +define+WAVES"
	cd build_trace && ./sim +TEST=$(TEST) +WAVE +verilator+seed+$(SEED)
	@echo "waveform: build_trace/wave.vcd   (gtkwave build_trace/wave.vcd)"

cov:
	$(MAKE) build BUILD=build_cov VMAIN="--cc --exe --build $(CURDIR)/tb/cov_main.cpp" VEXTRA="--coverage"
	cd build_cov && ./sim +TEST=all +verilator+seed+$(SEED)
	verilator_coverage --annotate build_cov/annot build_cov/coverage.dat
	@echo "annotated sources: build_cov/annot/"

clean:
	rm -rf build build_trace build_cov *.vcd coverage.dat obj_dir

help:
	@sed -n '2,11p' Makefile
