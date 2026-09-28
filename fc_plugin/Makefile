# bpf_conformance plugin for Femto-Container (the successor of RIOT's rBPF).

CC ?= cc
CFLAGS ?= -O2
BUILD_DIR ?= build
FEMTO_DIR := ../external/femto-container
PLUGIN := $(BUILD_DIR)/fc_plugin

# The VM's own sources, as listed in $(FEMTO_DIR)/src/meson.build.
FEMTO_SRCS := $(FEMTO_DIR)/src/bpf.c $(FEMTO_DIR)/src/jumptable.c $(FEMTO_DIR)/src/verify.c

# FEMTO_CONTAINER_EXTERNAL_CALLS: use our f12r_get_external_call (helper table)
#   instead of the stub in config.h; fc_ext.h declares it for the VM sources.
# FEMTO_CONTAINER_ENABLE_ALU32: 32-bit ALU instructions are off by default.
# gnu11: the VM uses computed gotos and range initializers.
FC_CFLAGS := -std=gnu11 \
	-DFEMTO_CONTAINER_EXTERNAL_CALLS \
	-DFEMTO_CONTAINER_ENABLE_ALU32=1 \
	-include fc_ext.h \
	-I$(FEMTO_DIR)/include -I.

.DEFAULT_GOAL := all

.PHONY: all clean

all: $(PLUGIN)

$(PLUGIN): fc_plugin.c fc_ext.h $(FEMTO_SRCS)
	mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(FC_CFLAGS) fc_plugin.c $(FEMTO_SRCS) -o $@

clean:
	rm -rf $(BUILD_DIR)
