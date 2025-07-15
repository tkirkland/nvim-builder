# Neovim .deb Builder

A secure bash script that compiles Neovim from source and creates a Debian package (.deb) with proper system integration.

## Features

- 🔧 **Automated Build**: Compiles Neovim from source with multi-core optimization
- 📦 **Modern Package Creation**: Uses dpkg-deb instead of checkinstall for better security
- 🚫 **No Root Required**: Build process runs without root privileges
- 🔄 **Auto Dependencies**: Automatically installs missing build dependencies
- 🔗 **System Integration**: Registers vi/vim/editor alternatives automatically  
- 🛡️ **Security Hardened**: Input validation and rootless build process
- ⚙️ **Configurable**: Customizable install prefix, build type, and package name
- 🧹 **Clean Output**: Minimal spam with clear status messages
- ⚡ **Fast Build**: Multi-core compilation for faster builds

## Quick Start

```bash
# Basic build (creates neovim.deb in current directory)
./build_nvim.sh

# Install the created package
sudo dpkg -i neovim_*.deb
```

## Requirements

### System Dependencies
The script automatically installs missing dependencies:
- `git` - Version control
- `cmake` - Build system
- `ninja-build` - Build tool
- `gettext` - Internationalization
- `unzip` - Archive extraction
- `curl` - HTTP client
- `dpkg-dev` - Debian package tools
- `fakeroot` - Privilege simulation for packaging

### Manual Installation (if needed)
```bash
sudo apt-get update
sudo apt-get install git cmake ninja-build gettext unzip curl dpkg-dev fakeroot
```

> **Note**: The script will automatically install any missing dependencies when you run it.

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

1. **Auto-Installs Dependencies**: Automatically installs any missing build tools
2. **Sets Up Environment**: Creates secure temporary build directory  
3. **Downloads Source**: Clones Neovim repository and checks out stable branch
4. **Multi-Core Compilation**: Builds Neovim using all available CPU cores
5. **Creates Package Structure**: Uses DESTDIR to create proper package layout
6. **Generates .deb Package**: Uses dpkg-deb for secure, rootless package creation
7. **No Installation**: Only creates the package - you choose when to install
8. **Cleanup**: Removes temporary files and ensures proper ownership

## System Integration

### Alternatives Registration
When you install the package, it automatically registers Neovim as an alternative for:
- `vi` - Traditional vi editor
- `vim` - Vim editor  
- `vim.tiny` - Minimal vim
- `editor` - System default editor
- `ex` - Ex editor mode
- `view` - Read-only editor
- `rview` - Restricted read-only editor
- `rvim` - Restricted vim
- `vimdiff` - Diff tool

The installation shows clean output like:
```
/usr/bin/nvim to provide /usr/bin/vi
/usr/bin/nvim to provide /usr/bin/vim
/usr/bin/nvim to provide /usr/bin/editor
```

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

- ✅ **Rootless Build**: No root privileges required during compilation
- ✅ **Input Validation**: All parameters validated against safe patterns
- ✅ **Path Sanitization**: Prevents command injection in file operations
- ✅ **Minimal Privileges**: Only uses sudo for dependency installation and final package installation
- ✅ **Standard Tools**: Uses only built-in Debian packaging tools
- ✅ **Secure Defaults**: Safe temporary directories and file permissions

## Troubleshooting

### Build Fails
```bash
# The script auto-installs dependencies, but if issues persist:

# Clean retry with fresh build
rm -rf /tmp/neovim-* && ./build_nvim.sh

# Check for specific errors in build output
./build_nvim.sh 2>&1 | grep -i "error"
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
- **Package**: `neovim_<version>_<arch>.deb` in script directory
- **Binary**: `/usr/bin/nvim` (or custom prefix) - *only after installation*
- **Man Pages**: `/usr/share/man/man1/nvim.1.gz` - *only after installation*
- **Alternatives**: System-wide editor alternatives - *only after installation*

## Build vs Install

This script **only builds** the .deb package. It does **not** install Neovim on your system.

### To Install After Building:
```bash
# Install the package you just built
sudo dpkg -i neovim_*.deb

# Fix any dependency issues (if needed)
sudo apt-get install -f
```

### Why Separate Build and Install?
- **Security**: You control when system changes happen
- **Testing**: You can examine the package before installing
- **Distribution**: You can copy the .deb to other systems
- **Safety**: No risk of breaking your current editor setup during build

## Contributing

1. Run security scan before changes: `./scan_security.sh`
2. Test on clean system
3. Verify package installation/removal
4. Check alternatives registration

## License

This script is provided as-is for building Neovim packages. Neovim itself is licensed under Apache 2.0.