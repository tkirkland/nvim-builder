#!/bin/bash

# Neovim .deb Build Script
# This script compiles Neovim from source and creates a .deb package

set -e

# Configuration
INSTALL_PREFIX="/usr"
BUILD_TYPE="Release"
PACKAGE_NAME="neovim"
CLEANUP_OLD_DEBS=true
CHECKOUT_STABLE=true
REGISTER_ALTERNATIVES=true
BUILD_DIR=$(mktemp -d /tmp/neovim-XXXX)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_USER="${SUDO_USER:-$USER}"
ORIGINAL_GROUP="$(id -gn "$ORIGINAL_USER")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
  local cmd
  print_status "Checking dependencies..."

  local missing_deps=()
  local missing_packages=()

  # Check for required commands and their corresponding packages
  declare -A deps=(
     ["git"]="git"
     ["cmake"]="cmake"
     ["ninja"]="ninja-build"
     ["gettext"]="gettext"
     ["unzip"]="unzip"
     ["curl"]="curl"
     ["dpkg-deb"]="dpkg-dev"
     ["fakeroot"]="fakeroot"
  )

  for cmd in "${!deps[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
      missing_packages+=("${deps[$cmd]}")
    fi
  done

  if [ ${#missing_deps[@]} -ne 0 ]; then
    print_warning "Missing dependencies: ${missing_deps[*]}"
    print_status "Installing missing packages: ${missing_packages[*]}"
    
    # Update package lists first
    print_status "Updating package lists..."
    if ! sudo apt-get update > /dev/null 2>&1; then
      print_error "Failed to update package lists"
      exit 1
    fi
    
    # Install missing packages
    print_status "Installing packages..."
    if ! sudo apt-get install -y "${missing_packages[@]}" > /dev/null 2>&1; then
      print_error "Failed to install missing packages: ${missing_packages[*]}"
      print_status "You can install them manually with:"
      echo "sudo apt-get install ${missing_packages[*]}"
      exit 1
    fi
    
    print_success "Successfully installed missing dependencies"
  fi

  print_success "All dependencies are available"
}

cleanup_old_files() {
  if [ "$CLEANUP_OLD_DEBS" = true ]; then
    print_status "Cleaning up old .deb files in script directory..."
    rm -f "$SCRIPT_DIR"/neovim*.deb
    print_success "Old .deb files removed"
  fi
}

setup_build_environment() {
  print_status "Setting up build environment in $BUILD_DIR..."

  # Directory should already exist from mktemp, but verify
  if [ ! -d "$BUILD_DIR" ]; then
    print_error "Build directory was not created successfully: $BUILD_DIR"
    exit 1
  fi

  # Cleanup function for exit
  trap cleanup_build_environment EXIT

  print_success "Build environment ready at: $BUILD_DIR"
}

cleanup_build_environment() {
  if [ -d "$BUILD_DIR" ]; then
    print_status "Cleaning up build environment..."
    rm -rf "$BUILD_DIR"
  fi
}

clone_or_update_repo() {
  # Ensure the build directory exists first
  if [ ! -d "$BUILD_DIR" ]; then
    print_error "Build directory $BUILD_DIR does not exist"
    exit 1
  fi

  cd "$BUILD_DIR"

  if [ ! -d "neovim" ]; then
    print_status "Cloning Neovim repository to $BUILD_DIR..."
    git clone https://github.com/neovim/neovim.git > /dev/null 2>&1
    cd neovim
  else
    print_status "Using existing Neovim repository in $BUILD_DIR..."
    cd neovim
    git fetch origin > /dev/null 2>&1
  fi
}

checkout_version() {
  if [ "$CHECKOUT_STABLE" = true ]; then
    print_status "Checking out stable branch..."
    git checkout stable > /dev/null 2>&1
    git pull origin stable > /dev/null 2>&1
  else
    print_status "Using current branch/commit"
  fi

  local version
  version=$(git describe --tags | sed 's/^v//')
  print_status "Building version: $version"
}

build_neovim() {
  print_status "Cleaning previous build..."
  make distclean > /dev/null 2>&1 || true

  print_status "Building Neovim..."
  print_status "Install prefix: $INSTALL_PREFIX"
  print_status "Build type: $BUILD_TYPE"

  make -j"$(nproc)" CMAKE_BUILD_TYPE="$BUILD_TYPE" CMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" > /dev/null 2>&1

  print_success "Build completed successfully"
}

create_package_structure() {
  print_status "Creating package directory structure..."
  
  local version
  version=$(git describe --tags | sed 's/^v//')
  
  # Validate version string for package safety
  if [[ ! $version =~ ^[a-zA-Z0-9][a-zA-Z0-9+.~-]*$ ]]; then
    print_error "Invalid version format: $version. Contains unsafe characters."
    exit 1
  fi
  
  # Create package directory structure
  PACKAGE_DIR="$BUILD_DIR/${PACKAGE_NAME}_${version}_$(dpkg --print-architecture)"
  DEBIAN_DIR="$PACKAGE_DIR/DEBIAN"
  
  print_status "Package directory: $PACKAGE_DIR"
  
  # Clean and create a package directory
  rm -rf "$PACKAGE_DIR"
  mkdir -p "$DEBIAN_DIR"
  
  # Install to package directory using DESTDIR
  print_status "Installing Neovim to package directory..."
  make install CMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" DESTDIR="$PACKAGE_DIR" > /dev/null 2>&1
  print_success "Package structure created successfully"
}

create_maintainer_scripts() {
  print_status "Creating maintainer scripts for alternatives..."

  local nvim_path="$INSTALL_PREFIX/bin/nvim"
  local nvim_manpage="$INSTALL_PREFIX/share/man/man1/nvim.1.gz"

  # Escape paths for safe sed substitution
  local nvim_path_escaped nvim_manpage_escaped
  nvim_path_escaped=$(printf '%s\n' "$nvim_path" | sed "s/[[\.\*^$()+?{|]/\\&/g")
  nvim_manpage_escaped=$(printf '%s\n' "$nvim_manpage" | sed "s/[[\.\*^$()+?{|]/\\&/g")

  # Create scripts in the DEBIAN directory
  print_status "Creating scripts in: $DEBIAN_DIR"

  # Create a postinst script (runs after package installation)
  cat > "$DEBIAN_DIR/postinst" << 'EOF'
#!/bin/bash
set -e

NVIM_PATH="__NVIM_PATH__"
NVIM_MANPAGE="__NVIM_MANPAGE__"


# Function to safely register alternatives
register_alternative() {
    local name=$1
    local link=$2
    local path=$3
    local priority=$4
    shift 4
    
    # Check if the binary exists
    if [ ! -f "$path" ]; then
        echo "Warning: $path not found, skipping $name alternative"
        return 1
    fi
    
    # Remove existing alternative if it points to a different path
    if update-alternatives --query "$name" >/dev/null 2>&1; then
        local current=$(update-alternatives --query "$name" 2>/dev/null | grep "Value:" | awk '{print $2}')
        if [ "$current" != "$path" ] && [ -n "$current" ]; then
            echo "Note: $name currently points to $current"
        fi
    fi
    
    # Build the update-alternatives command
    local cmd="update-alternatives --install \"$link\" \"$name\" \"$path\" $priority"
    
    # Add slaves if provided
    while [ $# -ge 3 ]; do
        local slave_link="$1"
        local slave_name="$2"
        local slave_path="$3"
        shift 3
        
        if [ -f "$slave_path" ]; then
            cmd="$cmd --slave \"$slave_link\" \"$slave_name\" \"$slave_path\""
        fi
    done
    
    # Execute the command
    if eval $cmd 2>/dev/null; then
        echo "$path to provide $link"
        return 0
    else
        echo "Warning: Failed to register $name alternative"
        return 1
    fi
}

echo "Registering neovim alternatives..."

register_alternative "vi" "/usr/bin/vi" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/vi.1.gz" "vi.1.gz" "$NVIM_MANPAGE"

register_alternative "vim" "/usr/bin/vim" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/vim.1.gz" "vim.1.gz" "$NVIM_MANPAGE"

register_alternative "vim.tiny" "/usr/bin/vim.tiny" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/vim.tiny.1.gz" "vim.tiny.1.gz" "$NVIM_MANPAGE"

register_alternative "editor" "/usr/bin/editor" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/editor.1.gz" "editor.1.gz" "$NVIM_MANPAGE"

register_alternative "ex" "/usr/bin/ex" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/ex.1.gz" "ex.1.gz" "$NVIM_MANPAGE"

register_alternative "view" "/usr/bin/view" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/view.1.gz" "view.1.gz" "$NVIM_MANPAGE"

register_alternative "rview" "/usr/bin/rview" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/rview.1.gz" "rview.1.gz" "$NVIM_MANPAGE"

register_alternative "rvim" "/usr/bin/rvim" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/rvim.1.gz" "rvim.1.gz" "$NVIM_MANPAGE"

register_alternative "vimdiff" "/usr/bin/vimdiff" "$NVIM_PATH" 60 \
    "/usr/share/man/man1/vimdiff.1.gz" "vimdiff.1.gz" "$NVIM_MANPAGE"

echo "To change defaults: sudo update-alternatives --config <command>"

exit 0
EOF

  # Replace placeholders in a postinst script with escaped paths
  sed -i "s|__NVIM_PATH__|$nvim_path_escaped|g" "$DEBIAN_DIR/postinst"
  sed -i "s|__NVIM_MANPAGE__|$nvim_manpage_escaped|g" "$DEBIAN_DIR/postinst"

  # Create prerm script (runs before package removal)
  cat > "$DEBIAN_DIR/prerm" << 'EOF'
#!/bin/bash
set -e

NVIM_PATH="__NVIM_PATH__"

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    echo "Removing neovim alternatives..."
    
    # Function to safely remove alternatives
    remove_alternative() {
        local name=$1
        local path=$2
        
        # Check if this alternative exists for our path
        if update-alternatives --list "$name" 2>/dev/null | grep -q "^$path$"; then
            if update-alternatives --remove "$name" "$path" 2>/dev/null; then
                echo "Removed $name alternative ($path)"
                return 0
            else
                echo "Warning: Failed to remove $name alternative"
                return 1
            fi
        fi
        return 0
    }
    
    # Remove all alternatives (matching vim's alternatives)
    for alt in vi vim vim.tiny editor ex view rview rvim vimdiff; do
        remove_alternative "$alt" "$NVIM_PATH"
    done
    
    echo "Neovim alternatives have been removed."
fi

exit 0
EOF

  # Replace placeholders in a prerm script with an escaped path
  sed -i "s|__NVIM_PATH__|$nvim_path_escaped|g" "$DEBIAN_DIR/prerm"

  # Create postrm script (runs after package removal)
  cat > "$DEBIAN_DIR/postrm" << 'EOF'
#!/bin/bash
set -e

NVIM_PATH="__NVIM_PATH__"

if [ "$1" = "purge" ]; then
    echo "Purging neovim configuration..."

    for alt in vi vim vim.tiny editor ex view rview rvim vimdiff; do
        if update-alternatives --list $alt 2>/dev/null | grep -q "^$NVIM_PATH$"; then
            update-alternatives --remove $alt "$NVIM_PATH" 2>/dev/null || true
        fi
    done

    for alt in vi vim vim.tiny editor ex view rview rvim vimdiff; do
        if update-alternatives --list $alt >/dev/null 2>&1; then
            update-alternatives --auto $alt 2>/dev/null || true
        fi
    done
fi

exit 0
EOF

  # Replace placeholders in a postrm script with an escaped path
  sed -i "s|__NVIM_PATH__|$nvim_path_escaped|g" "$DEBIAN_DIR/postrm"

  # Make scripts executable
  chmod 755 "$DEBIAN_DIR/postinst" "$DEBIAN_DIR/prerm" "$DEBIAN_DIR/postrm"

  # Verify scripts were created
  if [ -f "$DEBIAN_DIR/postinst" ] && [ -f "$DEBIAN_DIR/prerm" ] && [ -f "$DEBIAN_DIR/postrm" ]; then
    print_success "Maintainer scripts created successfully"
  else
    print_error "Failed to create maintainer scripts!"
    return 1
  fi
}

create_debian_control() {
  print_status "Creating DEBIAN/control file..."
  
  local version
  version=$(git describe --tags | sed 's/^v//')
  
  local description="A hyperextensible Vim-based text editor"
  
  cat > "$DEBIAN_DIR/control" << EOF
Package: $PACKAGE_NAME
Version: $version
Architecture: $(dpkg --print-architecture)
Maintainer: Neovim Build Script <build@localhost>
Depends: libc6, libgcc-s1, libstdc++6
Section: editors
Priority: optional
Description: $description
 Neovim is a modern text editor that builds on the heritage of Vim.
 It focuses on extensibility and usability while keeping the powerful
 modal editing paradigm that makes Vim unique.
 .
 This package was built from source using the nvim-builder script.
EOF

  print_success "DEBIAN/control file created"
}

create_deb_package() {
  print_status "Creating .deb package..."

  local version
  version=$(git describe --tags | sed 's/^v//')

  # Validate version string for package safety
  if [[ ! $version =~ ^[a-zA-Z0-9][a-zA-Z0-9+.~-]*$   ]]; then
    print_error "Invalid version format: $version. Contains unsafe characters."
    exit 1
  fi

  # We should be in the neovim build directory
  if [ ! -f "Makefile" ] || [ ! -d ".git" ]; then
    print_error "Not in the neovim build directory!"
    pwd
    exit 1
  fi

  # Create a package structure and install files
  create_package_structure

  # Create a DEBIAN/control file
  create_debian_control

  # Create maintainer scripts if alternatives are enabled
  if [ "$REGISTER_ALTERNATIVES" = true ]; then
    if ! create_maintainer_scripts; then
      print_error "Failed to create maintainer scripts!"
      exit 1
    fi
  fi

  # Build the package using dpkg-deb
  print_status "Building .deb package with dpkg-deb..."
  
  local deb_file
  deb_file=$(basename "$PACKAGE_DIR").deb
  
  # Use fakeroot or --root-owner-group for proper ownership
  if command -v fakeroot &> /dev/null; then
    print_status "Using fakeroot for package creation..."
    fakeroot dpkg-deb --build "$PACKAGE_DIR" "$BUILD_DIR/$deb_file" > /dev/null 2>&1
  else
    print_status "Using dpkg-deb with --root-owner-group..."
    dpkg-deb --build --root-owner-group "$PACKAGE_DIR" "$BUILD_DIR/$deb_file" > /dev/null 2>&1
  fi

  if [ -f "$BUILD_DIR/$deb_file" ]; then
    print_success ".deb package created: $deb_file"

    # Move to the script directory and fix ownership
    print_status "Moving .deb package to script directory..."
    cp "$BUILD_DIR/$deb_file" "$SCRIPT_DIR/"
    chown "$ORIGINAL_USER:$ORIGINAL_GROUP" "$SCRIPT_DIR/$deb_file"

    print_success "Package available at: $SCRIPT_DIR/$deb_file"

  else
    print_error "Failed to create .deb package!"
    exit 1
  fi

  print_success ".deb package creation completed"
}

register_alternatives() {
  # This function is no longer needed since alternatives are handled by package scripts
  if [ "$REGISTER_ALTERNATIVES" = true ]; then
    print_status "Alternatives will be registered by package maintainer scripts"
  fi
}

verify_installation() {
  local alt
  local deb
  print_status "Verifying installation..."

  if command -v nvim &> /dev/null; then
    local installed_version
    installed_version=$(nvim --version | head -1)
    print_success "Neovim installed successfully: $installed_version"

    # Check if binary is in expected location
    local nvim_path
    nvim_path=$(which nvim)
    print_status "Binary location: $nvim_path"

    # Check alternatives if registered
    if [ "$REGISTER_ALTERNATIVES" = true ]; then
      print_status "Alternative registrations:"
      for alt in vi vim vim.tiny editor ex view rview rvim vimdiff; do
        if update-alternatives --query $alt 2> /dev/null | grep -q "$INSTALL_PREFIX/bin/nvim"; then
          echo "  $alt -> registered"
        fi
      done
      print_status "Note: Alternatives are managed by the .deb package"
    fi

  else
    print_error "Neovim installation verification failed"
    exit 1
  fi
}

show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help              Show this help message"
  echo "  -p, --prefix PREFIX     Install prefix (default: $INSTALL_PREFIX)"
  echo "  -t, --type TYPE         Build type: Release|Debug (default: $BUILD_TYPE)"
  echo "  -n, --name NAME         Package name (default: $PACKAGE_NAME)"
  echo "  --no-cleanup            Don't remove old .deb files"
  echo "  --no-stable             Don't checkout stable branch"
  echo "  --no-alternatives       Don't register vi/vim/editor alternatives"
  echo ""
  echo "Examples:"
  echo "  $0                      # Build with defaults"
  echo "  $0 -p /usr/local        # Install to /usr/local"
  echo "  $0 -n neovim-latest     # Use different package name"
}

# Input validation functions
validate_prefix() {
  local prefix="$1"
  # Allow only safe absolute paths with alphanumeric, underscore, hyphen, slash
  if [[ ! $prefix =~ ^/[a-zA-Z0-9/_-]+$   ]]; then
    print_error "Invalid prefix: $prefix. Must be an absolute path with safe characters."
    exit 1
  fi
}

validate_build_type() {
  local build_type="$1"
  case "$build_type" in
    Release | Debug | RelWithDebInfo | MinSizeRel) ;; # Valid build types
    *)
      print_error "Invalid build type: $build_type. Must be Release, Debug, RelWithDebInfo, or MinSizeRel."
      exit 1
      ;;
  esac
}

validate_package_name() {
  local package_name="$1"
  # Debian package name rules: lowercase, alphanumeric, plus, hyphen, dot
  if [[ ! $package_name =~ ^[a-z0-9][a-z0-9+.-]*$   ]]; then
    print_error "Invalid package name: $package_name. Must follow Debian package naming rules."
    exit 1
  fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    show_usage
    exit 0
    ;;
  -p | --prefix)
    validate_prefix "$2"
    INSTALL_PREFIX="$2"
    shift 2
    ;;
  -t | --type)
    validate_build_type "$2"
    BUILD_TYPE="$2"
    shift 2
    ;;
  -n | --name)
    validate_package_name "$2"
    PACKAGE_NAME="$2"
    shift 2
    ;;
  --no-cleanup)
    CLEANUP_OLD_DEBS=false
    shift
    ;;
  --no-stable)
    CHECKOUT_STABLE=false
    shift
    ;;
  --no-alternatives)
    REGISTER_ALTERNATIVES=false
    shift
    ;;
  *)
    print_error "Unknown option: $1"
    show_usage
    exit 1
    ;;
  esac
done

# Main execution
main() {
  print_status "Starting Neovim .deb build process..."
  print_status "Configuration:"
  print_status "  Install prefix: $INSTALL_PREFIX"
  print_status "  Build type: $BUILD_TYPE"
  print_status "  Package name: $PACKAGE_NAME"
  print_status "  Checkout stable: $CHECKOUT_STABLE"
  print_status "  Build directory: $BUILD_DIR"
  print_status "  Script directory: $SCRIPT_DIR"
  print_status "  User/Group: $ORIGINAL_USER:$ORIGINAL_GROUP"
  print_status "  Register alternatives: $REGISTER_ALTERNATIVES"

  check_dependencies
  cleanup_old_files
  setup_build_environment
  clone_or_update_repo
  checkout_version
  build_neovim
  create_deb_package

  print_success "Build process completed successfully!"
  print_status "To install: sudo dpkg -i $SCRIPT_DIR/neovim_*.deb"
  if [ "$REGISTER_ALTERNATIVES" = true ]; then
    print_status "Alternatives will be registered automatically during installation"
  fi
}

# Run the main function
main "$@"
