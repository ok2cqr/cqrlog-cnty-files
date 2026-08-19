# DXCC parser -- Free Pascal reference implementation.
#
# Plain fpc on purpose: these units need neither Lazarus, nor the LCL, nor a
# database, and a build that needs none of those is a build any contributor
# can run.  There is no data-preparation step -- the tables are assembled from
# ../../data/dxcc by uDxccSource when the suite starts.
#
#   make            build the test runner
#   make test       run every test
#   make lookup     build tools/dxcclookup
#   make clean

FPC      ?= fpc
FPCFLAGS ?= -O1 -vw

# -WM sets the minimum macOS version and exists only in the Darwin compiler;
# passing it anywhere else makes fpc bail out with "Illegal parameter" before
# it compiles a line.  Keep it out of the portable flags, or the "any
# contributor can run this" claim above is false on Linux.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
FPCFLAGS += -WM11.0
endif

UNITPATHS = -Fusrc -Futests
OUTPUT    = -FUlib

BIN       = tests/dxcctests
LOOKUP    = tools/dxcclookup

SOURCES   = $(wildcard src/*.pas) $(wildcard tests/*.pas) tests/dxcctests.lpr

.PHONY: all test lookup clean help

all: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p lib
	$(FPC) $(FPCFLAGS) $(UNITPATHS) $(OUTPUT) -FEtests -o$(BIN) tests/dxcctests.lpr

test: $(BIN)
	./$(BIN) --format=plain --all

$(LOOKUP): $(wildcard src/*.pas) tools/dxcclookup.lpr
	@mkdir -p lib
	$(FPC) $(FPCFLAGS) $(UNITPATHS) $(OUTPUT) -FEtools -o$(LOOKUP) tools/dxcclookup.lpr

lookup: $(LOOKUP)

clean:
	rm -rf lib
	rm -f $(BIN) $(LOOKUP)

help:
	@echo "all test lookup clean"
