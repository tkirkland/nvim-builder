#!/bin/bash

# Neovim .deb Build Script
# This script compiles Neovim from source and creates a .deb package

set -e # Trap errors

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
     ["checkinstall"]="checkinstall"
  )

  for cmd in "${!deps[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
      missing_packages+=("${deps[$cmd]}")
    fi
  done

  if [ ${#missing_deps[@]} -ne 0 ]; then
    print_error "Missing dependencies: ${missing_deps[*]}"
    print_status "Install them with:"
    echo "sudo apt-get install ${missing_packages[*]}"
    exit 1
  fi

  print_success "All dependencies found"
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
    git clone https://github.com/neovim/neovim.git
    cd neovim
  else
    print_status "Using existing Neovim repository in $BUILD_DIR..."
    cd neovim
    git fetch origin
  fi
}

checkout_version() {
  if [ "$CHECKOUT_STABLE" = true ]; then
    print_status "Checking out stable branch..."
    git checkout stable
    git pull origin stable
  else
    print_status "Using current branch/commit"
  fi

  local version
  version=$(git describe --tags | sed 's/^v//')
  print_status "Building version: $version"
}

build_neovim() {
  print_status "Cleaning previous build..."
  make distclean 2> /dev/null || true

  print_status "Building Neovim..."
  print_status "Install prefix: $INSTALL_PREFIX"
  print_status "Build type: $BUILD_TYPE"

  make CMAKE_BUILD_TYPE="$BUILD_TYPE" CMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"

  print_success "Build completed successfully"
}

create_maintainer_scripts() {
  print_status "Creating maintainer scripts for alternatives..."

  local nvim_path="$INSTALL_PREFIX/bin/nvim"
  local nvim_manpage="$INSTALL_PREFIX/share/man/man1/nvim.1.gz"

  # Escape paths for safe sed substitution
  local nvim_path_escaped nvim_manpage_escaped
  nvim_path_escaped=$(printf '%s\n' "$nvim_path" | sed "s/[[\.\*^$()+?{|]/\\&/g")
  nvim_manpage_escaped=$(printf '%s\n' "$nvim_manpage" | sed "s/[[\.\*^$()+?{|]/\\&/g")

  # Create scripts in the current directory (should be BUILD_DIR/neovim)
  print_status "Creating scripts in: $(pwd)"

  # Create postinstall-pak script (runs after package installation)
  cat > postinstall-pak << 'EOF'
#!/bin/bash
set -e

NVIM_PATH="__NVIM_PATH__"
NVIM_MANPAGE="__NVIM_MANPAGE__"

echo "Setting up neovim alternatives..."

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
        echo "update-alternatives: using $path to provide $link ($name) in auto mode"
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

echo ""
echo "Neovim has been registered as an alternative for: vi, vim, vim.tiny, editor, ex, view, rview, rvim, vimdiff"
echo ""
echo "Current alternatives status:"
for alt in vi vim vim.tiny editor ex view rview rvim vimdiff; do
    if update-alternatives --query $alt >/dev/null 2>&1; then
        current=$(update-alternatives --query $alt 2>/dev/null | grep "Value:" | awk '{print $2}')
        if [ "$current" = "$NVIM_PATH" ]; then
            echo "  $alt → $current [*neovim*]"
        else
            echo "  $alt → $current"
        fi
    fi
done
echo ""
echo "To change defaults: sudo update-alternatives --config <command>"

exit 0
EOF

  # Replace placeholders in a postinstall script with escaped paths
  sed -i "s|__NVIM_PATH__|$nvim_path_escaped|g" postinstall-pak
  sed -i "s|__NVIM_MANPAGE__|$nvim_manpage_escaped|g" postinstall-pak

  # Create preremove-pak script (runs before package removal)
  cat > preremove-pak << 'EOF'
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

  # Replace placeholders in a preremove script with an escaped path
  sed -i "s|__NVIM_PATH__|$nvim_path_escaped|g" preremove-pak

  # Create postremove-pak script (runs after package removal)
  cat > postremove-pak << 'EOF'
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

  # Replace placeholders in a postremove script with an escaped path
  sed -i "s|__NVIM_PATH__|$nvim_path_escaped|g" postremove-pak

  # Make scripts executable
  chmod 755 postinstall-pak preremove-pak postremove-pak

  # Verify scripts were created
  if [ -f postinstall-pak ] && [ -f preremove-pak ] && [ -f postremove-pak ]; then
    print_success "Maintainer scripts created successfully"
  else
    print_error "Failed to create maintainer scripts!"
    return 1
  fi
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

  # IMPORTANT: We must be in the neovim build directory for checkinstall
  # Verify we're in the right directory
  if [ ! -f "Makefile" ] || [ ! -d ".git" ]; then
    print_error "Not in the neovim build directory!"
    pwd
    exit 1
  fi

  # Create maintainer scripts in the current directory (where checkinstall will run)
  if [ "$REGISTER_ALTERNATIVES" = true ]; then
    print_status "Creating maintainer scripts in $(pwd)..."
    create_maintainer_scripts

    # Verify scripts were created
    if [ ! -f "postinstall-pak" ] || [ ! -f "preremove-pak" ] || [ ! -f "postremove-pak" ]; then
      print_error "Failed to create maintainer scripts!"
      exit 1
    fi

    print_status "Maintainer scripts created successfully"
    ls -la ./*install-pak ./*remove-pak
  fi

  # Run checkinstall (it will pick up the maintainer scripts from the current directory)
  sudo checkinstall \
    --pkgname="$PACKAGE_NAME" \
    --pkgversion="$version" \
    --backup=no \
    --deldoc=yes \
    --fstrans=no \
    --default \
    make install

  # Clean up maintainer scripts after package creation
  if [ "$REGISTER_ALTERNATIVES" = true ]; then
    print_status "Cleaning up maintainer scripts..."
    rm -f postinstall-pak preinstall-pak preremove-pak postremove-pak
  fi

  # Move .deb file to script directory and change ownership
  local deb_file
  deb_file="${PACKAGE_NAME}_${version}-1_$(dpkg --print-architecture).deb"
  if [ -f "$deb_file" ]; then
    print_status "Moving .deb to script directory and setting ownership..."
    mv "$deb_file" "$SCRIPT_DIR/"
    chown "$ORIGINAL_USER:$ORIGINAL_GROUP" "$SCRIPT_DIR/$deb_file"
    print_success ".deb package created at: $SCRIPT_DIR/$deb_file"

    # Verify alternatives scripts are in the package
    if [ "$REGISTER_ALTERNATIVES" = true ]; then
      print_status "Verifying maintainer scripts in package..."
      if dpkg-deb --info "$SCRIPT_DIR/$deb_file" | grep -q "postinst"; then
        print_success "Maintainer scripts successfully included in .deb"
      else
        print_warning "Maintainer scripts may not be included in .deb!"
      fi
    fi
  else
    # Fallback: find any .deb file created
    local found_deb
    found_deb=$(find . -name "*.deb" -type f | head -1)
    if [ -n "$found_deb" ]; then
      print_status "Moving .deb to script directory and setting ownership..."
      mv "$found_deb" "$SCRIPT_DIR/"
      chown "$ORIGINAL_USER:$ORIGINAL_GROUP" "$SCRIPT_DIR/$(basename "$found_deb")"
      print_success ".deb package created at: $SCRIPT_DIR/$(basename "$found_deb")"

      # Verify alternatives scripts are in the package
      if [ "$REGISTER_ALTERNATIVES" = true ]; then
        print_status "Verifying maintainer scripts in package..."
        if dpkg-deb --info "$SCRIPT_DIR/$(basename "$found_deb")" | grep -q "postinst"; then
          print_success "Maintainer scripts successfully included in .deb"
        else
          print_warning "Maintainer scripts may not be included in .deb!"
        fi
      fi
    else
      print_warning "Could not find created .deb file"
    fi
  fi
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

    # List created .deb files in the script directory
    local deb_files=("$SCRIPT_DIR"/neovim*.deb)
    if [ -e "${deb_files[0]}" ]; then
      print_success "Created .deb file(s) in script directory:"
      for deb in "${deb_files[@]}"; do
        echo "  $(basename "$deb") (owned by $ORIGINAL_USER:$ORIGINAL_GROUP)"
      done
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
  register_alternatives
  verify_installation

  print_success "Build process completed successfully!"
  print_status "To uninstall: sudo apt remove $PACKAGE_NAME"
  if [ "$REGISTER_ALTERNATIVES" = true ]; then
    print_status "Alternatives will be automatically removed on uninstall"
  fi
}

# Run the main function
main "$@"
