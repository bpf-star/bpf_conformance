# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

BUILD_DIR ?= build
RUNNER := $(BUILD_DIR)/bin/bpf_conformance_runner
LIBBPF_PLUGIN := $(BUILD_DIR)/bin/libbpf_plugin
ALIVIO_PLUGIN := $(BUILD_DIR)/bin/alivio_plugin
PREVAIL_PLUGIN := $(BUILD_DIR)/bin/prevail_plugin
RBPF_PLUGIN := $(CURDIR)/rbpf_plugin/target/release/rbpf_plugin
FC_PLUGIN := $(CURDIR)/fc_plugin/build/fc_plugin

ALIVIO_DIR := $(CURDIR)/external/alivio
PREVAIL_DIR := $(CURDIR)/external/prevail
PREVAIL_BUILD_DIR ?= $(PREVAIL_DIR)/build
ALIVIO_DEFAULT := $(ALIVIO_DIR)/target/release/alivio
PREVAIL_DEFAULT := $(PREVAIL_DIR)/bin/prevail
ALIVIO ?= $(ALIVIO_DEFAULT)
PREVAIL ?= $(PREVAIL_DEFAULT)
PREVAIL_CMAKE_OPTIONS ?= -DCMAKE_BUILD_TYPE=Release
SUDO ?= sudo

# rbpf execution mode: --interpret or --jit (x86-64 only)
RBPF_PLUGIN_OPTIONS ?= --interpret

ifeq ($(shell uname -s),Darwin)
HOMEBREW_PREFIX ?= $(shell brew --prefix)
PREVAIL_BUILD_ENV ?= CPATH=$(HOMEBREW_PREFIX)/include LIBRARY_PATH=$(HOMEBREW_PREFIX)/lib CMAKE_PREFIX_PATH=$(HOMEBREW_PREFIX)
PREVAIL_CMAKE_OPTIONS += -DCMAKE_C_COMPILER=$(HOMEBREW_PREFIX)/opt/llvm/bin/clang -DCMAKE_CXX_COMPILER=$(HOMEBREW_PREFIX)/opt/llvm/bin/clang++
else
PREVAIL_BUILD_ENV ?=
endif

ifneq ($(strip $(TEST)),)
TEST_INPUT := --test_file_path "$(abspath $(TEST))"
ISA_TEST_INPUT := $(TEST_INPUT)
else
TEST_INPUT := --test_file_directory "$(CURDIR)/verifier_tests"
ISA_TEST_INPUT := --test_file_directory "$(CURDIR)/tests"
endif

VERIFIER_OPTIONS := \
	$(TEST_INPUT) \
	--cpu_version v4 \
	--verifier true \
	--xdp_prolog true

# Runtime (ISA) conformance: run the programs in tests/ and check r0.
ISA_OPTIONS := \
	$(ISA_TEST_INPUT) \
	--cpu_version v4

.DEFAULT_GOAL := all

.PHONY: all clean cleanall test linux alivio prevail ensure-alivio ensure-prevail \
	rbpf fc rbpf-plugin fc-plugin

all:
	cmake -S . -B $(BUILD_DIR)
	cmake --build $(BUILD_DIR)

clean:
	cmake --build $(BUILD_DIR) --target clean

cleanall:
	cmake -E remove_directory "$(BUILD_DIR)"

test:
	cmake --build $(BUILD_DIR) --target test --

linux: all
	$(SUDO) "$(RUNNER)" \
		$(VERIFIER_OPTIONS) \
		--exclude_regex "imm-" \
		--plugin_path "$(LIBBPF_PLUGIN)" \
		--plugin_options="--verify-only"

# Rebuild the verifiers from their submodules on every run (incremental).
# User can optionally specify ALIVIO/PREVAIL binary path built elsewhere. In such cases
# the command will only test whether the binary exists.
ensure-alivio:
ifeq ($(ALIVIO),$(ALIVIO_DEFAULT))
	cargo build --release --manifest-path "$(ALIVIO_DIR)/Cargo.toml"
endif
	@test -x "$(ALIVIO)" || { echo "Alivio executable not found at $(ALIVIO)" >&2; exit 1; }

ensure-prevail:
ifeq ($(PREVAIL),$(PREVAIL_DEFAULT))
	test -f "$(PREVAIL_BUILD_DIR)/CMakeCache.txt" || \
		$(PREVAIL_BUILD_ENV) cmake -S "$(PREVAIL_DIR)" -B "$(PREVAIL_BUILD_DIR)" $(PREVAIL_CMAKE_OPTIONS)
	$(PREVAIL_BUILD_ENV) cmake --build "$(PREVAIL_BUILD_DIR)" --target prevail-cli
endif
	@test -x "$(PREVAIL)" || { echo "Prevail executable not found at $(PREVAIL)" >&2; exit 1; }

alivio: all ensure-alivio
	"$(RUNNER)" \
		$(VERIFIER_OPTIONS) \
		--elf true \
		--plugin_path "$(ALIVIO_PLUGIN)" \
		--plugin_options="--alivio $(ALIVIO)"

prevail: all ensure-prevail
	"$(RUNNER)" \
		$(VERIFIER_OPTIONS) \
		--elf true \
		--plugin_path "$(PREVAIL_PLUGIN)" \
		--plugin_options="--prevail $(PREVAIL)"

# Always invoke the plugin builds; cargo and make rebuild only what changed.
rbpf-plugin:
	cargo build --release --manifest-path rbpf_plugin/Cargo.toml

fc-plugin:
	$(MAKE) -C fc_plugin

rbpf: all rbpf-plugin
	"$(RUNNER)" \
		$(ISA_OPTIONS) \
		--plugin_path "$(RBPF_PLUGIN)" \
		--plugin_options="$(RBPF_PLUGIN_OPTIONS)"

fc: all fc-plugin
	"$(RUNNER)" \
		$(ISA_OPTIONS) \
		--plugin_path "$(FC_PLUGIN)"
