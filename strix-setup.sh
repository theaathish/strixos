#!/bin/bash
# STRIX OS AUTO INSTALL SCRIPT
# Created on: 2025-04-21 15:42:26

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration variables
DEBUG=false
MANUAL_MODE=false
LOG_FILE="/tmp/strix-install.log"
CURRENT_STEP=1
TOTAL_STEPS=9

# Initialize log file
> "$LOG_FILE"

# Function definitions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}[DEBUG] $1${NC}"
    fi
}

print_header() {
    echo -e "\n${PURPLE}=====================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}=====================================${NC}"
}

print_step() {
    echo -e "\n${GREEN}>>> [$CURRENT_STEP/$TOTAL_STEPS] $1${NC}"
    log "Starting step $CURRENT_STEP: $1"
    CURRENT_STEP=$((CURRENT_STEP+1))
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
    log "INFO: $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
    log "ERROR: $1"
}

handle_error() {
    print_error "$1"
    print_error "Check $LOG_FILE for details"
    if [ "$MANUAL_MODE" = true ]; then
        print_info "You are in manual mode. Fix the issue and continue."
        read -p "Press Enter to continue or type 'exit' to abort: " choice
        if [ "$choice" = "exit" ]; then
            print_info "Installation aborted by user."
            exit 1
        fi
    else
        print_info "Switching to manual mode to resolve the issue."
        MANUAL_MODE=true
        read -p "Press Enter to continue or type 'exit' to abort: " choice
        if [ "$choice" = "exit" ]; then
            print_info "Installation aborted by user."
            exit 1
        fi
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_warning "Command '$1' could not be found"
        return 1
    fi
    return 0
}

confirm_step() {
    if [ "$MANUAL_MODE" = true ]; then
        read -p "Confirm to proceed with this step? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            print_info "Step skipped by user. Proceeding to next step."
            return 1
        fi
    fi
    return 0
}

# Command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            DEBUG=true
            print_info "Debug mode enabled"
            ;;
        --manual)
            MANUAL_MODE=true
            print_info "Manual mode enabled"
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "  --debug    Enable debug mode"
            echo "  --manual   Enable manual confirmation for each step"
            echo "  --help     Display this help message"
            exit 0
            ;;
        *)
            print_warning "Unknown option: $1"
            ;;
    esac
    shift
done

# Display welcome message
print_header "STRIX OS INSTALLATION"
print_info "This script will guide you through the installation of Strix OS"
print_info "Log file: $LOG_FILE"
if [ "$DEBUG" = true ]; then print_info "Debug mode: Enabled"; fi
if [ "$MANUAL_MODE" = true ]; then print_info "Manual mode: Enabled"; fi

# Set error handling
set -e
trap 'handle_error "An error occurred at line $LINENO. Command: $BASH_COMMAND"' ERR

# Start installation
print_step "Setting up Internet"
if confirm_step; then
    print_info "Starting network connection wizard"
    if ! check_command iwctl; then
        print_warning "iwctl command not found. Network setup may fail."
    fi
    
    # Try to connect to the internet
    (iwctl || true) && log "iwctl completed"
    
    print_info "Testing internet connection..."
    if ping -c 3 archlinux.org &>> "$LOG_FILE"; then
        print_info "Internet connection successful"
    else
        handle_error "Internet connection failed. Please configure the network manually."
    fi
fi

print_step "Partitioning Disk"
if confirm_step; then
    print_info "Manual partitioning recommended for data safety"
    print_info "Use fdisk or cfdisk to create:"
    print_info "  - EFI partition (/dev/sda1, 512MB, FAT32)"
    print_info "  - Swap partition (/dev/sda2, RAM size, SWAP)"
    print_info "  - Root partition (/dev/sda3, Remaining space, EXT4)"
    
    if [ "$MANUAL_MODE" = true ]; then
        PS3="Select a partitioning tool: "
        select tool in "fdisk" "cfdisk" "parted" "skip"; do
            case $tool in
                "fdisk")
                    fdisk /dev/sda
                    break
                    ;;
                "cfdisk")
                    cfdisk /dev/sda
                    break
                    ;;
                "parted")
                    parted /dev/sda
                    break
                    ;;
                "skip")
                    print_warning "Partitioning skipped. Make sure partitions exist."
                    break
                    ;;
                *)
                    print_error "Invalid option"
                    ;;
            esac
        done
    else
        read -p "Press Enter once partitioning is complete..."
    fi
    
    # Verify partitions
    print_info "Verifying partitions..."
    if ! fdisk -l /dev/sda &>> "$LOG_FILE"; then
        handle_error "Failed to list partitions. Check if disk exists and partitioning was done correctly."
    fi
fi

print_step "Formatting Partitions"
if confirm_step; then
    print_info "Formatting EFI partition (/dev/sda1)"
    if ! mkfs.fat -F32 /dev/sda1 &>> "$LOG_FILE"; then
        handle_error "Failed to format EFI partition"
    fi
    
    print_info "Formatting root partition (/dev/sda3)"
    if ! mkfs.ext4 /dev/sda3 &>> "$LOG_FILE"; then
        handle_error "Failed to format root partition"
    fi
    
    print_info "Creating and activating swap (/dev/sda2)"
    if ! mkswap /dev/sda2 &>> "$LOG_FILE"; then
        handle_error "Failed to create swap"
    fi
    
    if ! swapon /dev/sda2 &>> "$LOG_FILE"; then
        handle_error "Failed to activate swap"
    fi
    
    print_info "All partitions formatted successfully"
fi

print_step "Mounting Partitions"
if confirm_step; then
    print_info "Mounting root partition to /mnt"
    if ! mount /dev/sda3 /mnt &>> "$LOG_FILE"; then
        handle_error "Failed to mount root partition"
    fi
    
    print_info "Creating and mounting EFI directory"
    if ! mkdir -p /mnt/boot/efi &>> "$LOG_FILE"; then
        handle_error "Failed to create EFI directory"
    fi
    
    if ! mount /dev/sda1 /mnt/boot/efi &>> "$LOG_FILE"; then
        handle_error "Failed to mount EFI partition"
    fi
    
    print_info "All partitions mounted successfully"
fi

print_step "Installing Base System"
if confirm_step; then
    print_info "This may take a while depending on your internet speed..."
    if ! pacstrap /mnt base linux linux-firmware sudo vim git networkmanager &>> "$LOG_FILE"; then
        handle_error "Failed to install base system"
    fi
    print_info "Base system installed successfully"
fi

print_step "Generating fstab"
if confirm_step; then
    print_info "Creating filesystem table..."
    if ! genfstab -U /mnt >> /mnt/etc/fstab; then
        handle_error "Failed to generate fstab"
    fi
    
    print_info "Verifying fstab..."
    cat /mnt/etc/fstab
    print_info "fstab generated successfully"
fi

print_step "Chroot and Configuration"
if confirm_step; then
    print_info "Preparing chroot environment and configuring system..."
    
    # Create a temporary script to run inside chroot
    cat > /mnt/chroot_setup.sh <<EOF
#!/bin/bash
set -e

echo "[Chroot] Setting timezone..."
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

echo "[Chroot] Configuring locale..."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

echo "[Chroot] Setting hostname..."
echo strixos > /etc/hostname

echo "[Chroot] Configuring hosts file..."
cat > /etc/hosts <<HOSTS
127.0.0.1 localhost
::1       localhost
127.0.1.1 strixos.localdomain strixos
HOSTS

echo "[Chroot] Installing bootloader..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=STRIX
grub-mkconfig -o /boot/grub/grub.cfg

echo "[Chroot] Installing GNOME and enabling services..."
pacman -S --noconfirm gnome gdm gnome-tweaks gnome-control-center gnome-terminal xorg
systemctl enable gdm
systemctl enable NetworkManager

echo "[Chroot] Setting up Strix Package Manager..."
mkdir -p /opt
cd /opt
git clone https://github.com/theaathish/strix-os.git
cd strix-os
chmod +x setup.sh
./setup.sh

echo "[Chroot] Configuration complete!"
EOF

    # Make the script executable
    chmod +x /mnt/chroot_setup.sh
    
    # Execute the script in chroot
    if ! arch-chroot /mnt /chroot_setup.sh &>> "$LOG_FILE"; then
        handle_error "Chroot configuration failed"
    fi
    
    # Clean up
    rm /mnt/chroot_setup.sh
    print_info "System configuration completed successfully"
fi

print_step "Finalizing Installation"
if confirm_step; then
    print_info "Unmounting partitions..."
    sync
    umount -R /mnt &>> "$LOG_FILE" || print_warning "Failed to unmount partitions, but installation may still be successful"
    
    print_info "Installation completed successfully!"
    print_header "🎉 STRIX OS INSTALLATION COMPLETE 🎉"
    print_info "You can now reboot into Strix OS"
    print_info "Installation log saved to: $LOG_FILE"
    
    if [ "$MANUAL_MODE" = true ]; then
        read -p "Would you like to reboot now? (y/n): " reboot_choice
        if [ "$reboot_choice" = "y" ]; then
            print_info "Rebooting system..."
            reboot
        else
            print_info "You can reboot manually when ready by typing 'reboot'"
        fi
    else
        print_info "Type 'reboot' to start your new Strix OS"
    fi
fi
