# Neovim .deb Builder

A secure bash script that compiles Neovim from source and creates a Debian package (.deb) with proper system integration.

## Features

- 🔧 **Automated Build**: Compiles Neovim from source with optimized settings
- 📦 **Package Creation**: Creates installable .deb packages using checkinstall
- 🔗 **System Integration**: Registers vi/vim/editor alternatives automatically
- 🛡️ **Security Hardened**: Input validation and injection protection
- ⚙️ **Configurable**: Customizable install prefix, build type, and package name
- 🧹 **Clean Build**: Uses temporary directories with automatic cleanup

## Quick Start

```bash
# Basic build (creates neovim.deb in current directory)
./build_nvim.sh

# Install the created package
sudo dpkg -i neovim_*.deb
```

## Requirements

### System Dependencies
The script will check for and guide you to install:
- `git` - Version control
- `cmake` - Build system
- `ninja-build` - Build tool
- `gettext` - Internationalization
- `unzip` - Archive extraction
- `curl` - HTTP client
- `checkinstall` - Package creation

### Install Dependencies (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install git cmake ninja-build gettext unzip curl checkinstall
```

## Usage

### Basic Usage
```bash
./build_nvim.sh [OPTIONS]
```

### Options
- `-h, --help` - Show help message
- `-p, --prefix PREFIX` - Install prefix (default: `/usr`)
- `-t, --type TYPE` - Build type: Release|Debug|RelWithDebInfo|MinSizeRel (default: `Release`)
- `-n, --name NAME` - Package name (default: `neovim`)
- `--no-cleanup` - Don't remove old .deb files
- `--no-stable` - Don't checkout stable branch (use current branch)
- `--no-alternatives` - Don't register vi/vim/editor alternatives

### Examples

```bash
# Install to /usr/local instead of /usr
./build_nvim.sh --prefix /usr/local

# Create debug build
./build_nvim.sh --type Debug

# Custom package name
./build_nvim.sh --name neovim-latest

# Build current branch without alternatives
./build_nvim.sh --no-stable --no-alternatives

# Complete custom build
./build_nvim.sh --prefix /opt/neovim --type RelWithDebInfo --name neovim-custom
```

## What It Does

1. **Validates Dependencies**: Checks for required build tools
2. **Sets Up Environment**: Creates secure temporary build directory
3. **Downloads Source**: Clones Neovim repository and checks out stable branch
4. **Compiles**: Builds Neovim with specified configuration
5. **Creates Package**: Uses checkinstall to create .deb with maintainer scripts
6. **Registers Alternatives**: Sets up system alternatives for vi, vim, editor commands
7. **Cleanup**: Removes temporary files and sets proper ownership

## System Integration

### Alternatives Registration
The package automatically registers Neovim as an alternative for:
- `vi` - Traditional vi editor
- `vim` - Vim editor
- `vim.tiny` - Minimal vim
- `editor` - System default editor
- `ex` - Ex editor mode
- `view` - Read-only editor
- `rview` - Restricted read-only editor  
- `rvim` - Restricted vim
- `vimdiff` - Diff tool

### Managing Alternatives
```bash
# Check current alternatives
sudo update-alternatives --config editor

# See all alternatives for vim
update-alternatives --list vim

# Set specific alternative
sudo update-alternatives --set vi /usr/bin/nvim
```

## Package Management

### Installation
```bash
# Install created package
sudo dpkg -i neovim_*.deb

# Fix dependencies if needed
sudo apt-get install -f
```

### Removal
```bash
# Remove package (keeps alternatives)
sudo apt-get remove neovim

# Completely remove including alternatives
sudo apt-get purge neovim
```

## Security Features

- ✅ **Input Validation**: All parameters validated against safe patterns
- ✅ **Path Sanitization**: Prevents command injection in file operations
- ✅ **Privilege Control**: Minimal sudo usage with validated inputs
- ✅ **Secure Defaults**: Safe temporary directories and file permissions

## Troubleshooting

### Build Fails
```bash
# Check dependencies
./build_nvim.sh 2>&1 | grep -i "missing"

# Clean retry
rm -rf /tmp/neovim-* && ./build_nvim.sh
```

### Permission Errors
```bash
# Ensure script is executable
chmod +x build_nvim.sh

# Check sudo access
sudo -v
```

### Package Conflicts
```bash
# Remove existing vim/neovim packages
sudo apt-get remove vim neovim

# Clear alternatives
sudo update-alternatives --remove-all editor
```

## Output

The script creates:
- **Package**: `neovim_<version>-1_<arch>.deb` in script directory
- **Binary**: `/usr/bin/nvim` (or custom prefix)
- **Man Pages**: `/usr/share/man/man1/nvim.1.gz`
- **Alternatives**: System-wide editor alternatives

## Contributing

1. Run security scan before changes: `./scan_security.sh`
2. Test on clean system
3. Verify package installation/removal
4. Check alternatives registration

## License

This script is provided as-is for building Neovim packages. Neovim itself is licensed under Apache 2.0.