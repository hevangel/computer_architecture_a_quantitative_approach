# Top-level entry point. All logic lives in scripts/run_tests.py.
#   make test                      run every example, SV (iverilog) + VHDL (ghdl)
#   make test-sv | make test-vhdl  one language only
#   make test T=ch02               only modules whose path contains "ch02" (T may hold several words)
#   make lint                      Verilator lint of every SV example
#   make list                      list discovered examples
#   make clean
PY ?= python3
T  ?=

.PHONY: test test-sv test-vhdl lint list clean
test:      ; $(PY) scripts/run_tests.py $(T)
test-sv:   ; $(PY) scripts/run_tests.py --lang sv $(T)
test-vhdl: ; $(PY) scripts/run_tests.py --lang vhdl $(T)
lint:      ; $(PY) scripts/run_tests.py --lint $(T)
list:      ; $(PY) scripts/run_tests.py --list $(T)
clean:     ; rm -rf build
