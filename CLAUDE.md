# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a bash script for building Neovim from source and creating a .deb package. The script compiles Neovim with full dependency management, alternative registration, and proper package installation on Debian/Ubuntu systems.

## Common Development Tasks

### Building Neovim Package
```bash
# Basic build (creates .deb package in current directory)
./build_nvim.sh

# Build with custom install prefix
./build_nvim.sh --prefix /usr/local

# Build without registering vi/vim alternatives
./build_nvim.sh --no-alternatives

# Build using current branch instead of stable
./build_nvim.sh --no-stable

# Debug build
./build_nvim.sh --type Debug
```

### Script Testing and Validation
```bash
# Check script syntax
bash -n build_nvim.sh

# Run with bash debug mode
bash -x build_nvim.sh --help
```

## Architecture

The `build_nvim.sh` script follows these key phases:

1. **Dependency Checking**: Validates required tools (git, cmake, ninja, etc.)
2. **Environment Setup**: Creates temporary build directory with cleanup handling
3. **Repository Management**: Clones/updates Neovim source, optionally checks out stable branch
4. **Building**: Compiles Neovim with configurable CMAKE settings
5. **Package Creation**: Uses `checkinstall` to create .deb with maintainer scripts
6. **Alternative Registration**: Creates postinstall/preremove scripts for vi/vim alternatives

### Key Components

- **Maintainer Scripts**: Automatically generated postinstall/preremove scripts handle alternatives registration for vi, vim, editor, etc.
- **Configuration Variables**: Configurable install prefix, build type, package name, and feature flags
- **Error Handling**: Exit-on-error with proper cleanup and colored status output
- **Ownership Management**: Preserves original user ownership for created .deb files

### Build Dependencies

Required system packages:
- git, cmake, ninja-build, gettext, unzip, curl, checkinstall

### Output

Creates a .deb package that:
- Installs Neovim to specified prefix (default: /usr)
- Registers alternatives for vi, vim, vim.tiny, editor, ex, view, rview, rvim, vimdiff
- Properly handles package removal and cleanup