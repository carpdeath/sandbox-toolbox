GAME_DIR ?= $(HOME)/.local/share/Steam/steamapps/common/Manor Lords
MODS_DIR ?= $(GAME_DIR)/ManorLords/Binaries/Win64/ue4ss/Mods
MINGW_CC ?= x86_64-w64-mingw32-gcc

VERSION    := $(shell sed -n 's/.*return *"\([0-9.]*\)".*/\1/p' mod/SandboxToolbox/Scripts/toolbox/version.lua)
LUA_SRC    := $(shell find mod tools -name '*.lua')
MOD_FILES  := $(shell find mod -type f)
NATIVE_SRC := $(wildcard native/*.c native/*.h)
C_SRC      := $(NATIVE_SRC)
VENDOR     := $(shell find vendor/ModMenu -type f)

DLL     := build/native_bridge.dll
ZIP     := dist/SandboxToolbox-$(VERSION).zip
LINTED  := build/.linted

.PHONY: help lint format dll bundle install clean

help:
	@echo "make lint     syntax check + formatting check (stylua, clang-format)"
	@echo "make format   reformat Lua and C sources in place"
	@echo "make dll      build $(DLL) (needs mingw-w64)"
	@echo "make bundle   lint, build, and write $(ZIP)"
	@echo "make install  bundle, then copy the staged mod into MODS_DIR with debug on (default: Steam on Linux)"
	@echo "make clean    remove build/ and dist/"

lint: $(LINTED)
dll: $(DLL)
bundle: $(ZIP)

$(LINTED): $(LUA_SRC) $(C_SRC) .stylua.toml .clang-format
	@mkdir -p build
	luac5.4 -p $(LUA_SRC)
	stylua --check mod tools
	clang-format --dry-run -Werror $(C_SRC)
	@touch $@

$(DLL): $(NATIVE_SRC)
	@mkdir -p build
	$(MINGW_CC) -shared -O2 -Wl,--no-insert-timestamp -Wall -Wextra -Werror -o $@ native/native_bridge.c

$(ZIP): $(LINTED) $(DLL) $(MOD_FILES) $(VENDOR) LICENSE tools/bundle.py
	tools/bundle.py --prebuilt

install: $(ZIP)
	@rm -rf "$(MODS_DIR)/SandboxToolbox"
	@cp -r dist/stage/SandboxToolbox "$(MODS_DIR)/SandboxToolbox"
	@sed -i 's/^\( *debug = \)false,/\1true,/' "$(MODS_DIR)/SandboxToolbox/Scripts/toolbox/config.lua"
	@grep -q '^ *debug = true,' "$(MODS_DIR)/SandboxToolbox/Scripts/toolbox/config.lua" || { echo "could not enable debug in the installed config"; exit 1; }
	@test -f "$(MODS_DIR)/shared/ModMenu/ModMenu.lua" || { mkdir -p "$(MODS_DIR)/shared"; cp -r dist/stage/shared/ModMenu "$(MODS_DIR)/shared/ModMenu"; }
	@echo "Installed to $(MODS_DIR)"

format:
	stylua mod tools
	clang-format -i $(C_SRC)

clean:
	rm -rf build dist
