#!/bin/bash

# CARAXES Rootkit Uninstallation Script
# This script removes the CARAXES rootkit from the system

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

# Function to unload module
unload_module() {
    print_status "Checking if CARAXES module is loaded..."
    
    if lsmod | grep -q caraxes; then
        print_status "Unloading CARAXES module..."
        if sudo modprobe -r caraxes 2>/dev/null; then
            print_success "Module unloaded with modprobe"
        elif sudo rmmod caraxes 2>/dev/null; then
            print_success "Module unloaded with rmmod"
        else
            print_warning "Failed to unload module normally, trying force removal..."
            sudo rmmod -f caraxes 2>/dev/null || true
        fi
    else
        print_status "Module is not currently loaded"
    fi
}

# Function to remove module from system location
remove_module_files() {
    print_status "Removing module files from system..."
    
    # Remove module directory
    if [ -d "/lib/modules/$(uname -r)/kernel/drivers/caraxes" ]; then
        if sudo rm -rf /lib/modules/$(uname -r)/kernel/drivers/caraxes; then
            print_success "Removed module directory"
        else
            print_error "Failed to remove module directory"
        fi
    else
        print_status "Module directory not found (already removed)"
    fi
    
    # Update module dependencies
    print_status "Updating module dependencies..."
    sudo depmod -a
}

# Function to remove auto-load configuration
remove_autoload_config() {
    print_status "Removing auto-load configuration..."
    
    if [ -f "/etc/modules-load.d/caraxes.conf" ]; then
        if sudo rm -f /etc/modules-load.d/caraxes.conf; then
            print_success "Removed auto-load configuration"
        else
            print_error "Failed to remove auto-load configuration"
        fi
    else
        print_status "Auto-load configuration not found (already removed)"
    fi
}

# Function to clean local build files
clean_local_files() {
    print_status "Cleaning local build files..."
    
    if [ -f "Makefile" ]; then
        make clean 2>/dev/null || true
    fi
    
    rm -f *.ko *.o *.mod.c *.mod *.symvers *.order .*.cmd 2>/dev/null || true
    rm -rf .tmp_versions/ 2>/dev/null || true
    
    print_success "Local build files cleaned"
}

# Function to show final status
show_final_status() {
    echo
    print_success "CARAXES rootkit uninstallation complete!"
    echo
    echo -e "${BLUE}What was removed:${NC}"
    echo "- Module unloaded from kernel"
    echo "- Module files removed from /lib/modules/"
    echo "- Auto-load configuration removed"
    echo "- Local build files cleaned"
    echo
    echo -e "${GREEN}System Status:${NC}"
    if lsmod | grep -q caraxes; then
        print_warning "Module may still be loaded (check manually)"
    else
        print_success "Module is not loaded"
    fi
    
    if [ -d "/lib/modules/$(uname -r)/kernel/drivers/caraxes" ]; then
        print_warning "Module directory still exists"
    else
        print_success "Module directory removed"
    fi
    
    if [ -f "/etc/modules-load.d/caraxes.conf" ]; then
        print_warning "Auto-load configuration still exists"
    else
        print_success "Auto-load configuration removed"
    fi
    
    echo
    echo -e "${YELLOW}Note:${NC} You may need to reboot to ensure complete removal."
}

# Main uninstallation process
main() {
    echo -e "${BLUE}"
    echo "========================================="
    echo "  CARAXES Rootkit Uninstallation Script"
    echo "========================================="
    echo -e "${NC}"
    
    # Check if running with sufficient privileges
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        print_error "Please run with sudo or ensure you can use sudo"
        exit 1
    fi
    
    print_warning "This will completely remove the CARAXES rootkit from your system."
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Uninstallation cancelled"
        exit 0
    fi
    
    # Unload module
    unload_module
    
    # Remove module files
    remove_module_files
    
    # Remove auto-load configuration
    remove_autoload_config
    
    # Clean local files
    clean_local_files
    
    # Show final status
    show_final_status
}

# Run main function
main "$@"
