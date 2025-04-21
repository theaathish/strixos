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
DISK_DEVICE=""

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
    
    # Show recent log entries to help diagnose the issue
    print_info "Last 5 log entries:"
    tail -n 5 "$LOG_FILE" | while read -r line; do
        echo -e "  ${YELLOW}$line${NC}"
    done
    
    if [ "$MANUAL_MODE" = true ]; then
        print_info "You are in manual mode. Fix the issue and continue."
        echo -e "Options:"
        echo -e "  ${GREEN}c${NC} - Continue to next step"
        echo -e "  ${YELLOW}r${NC} - Retry current step"
        echo -e "  ${BLUE}s${NC} - Open a shell to debug"
        echo -e "  ${RED}e${NC} - Exit installation"
        
        read -p "Select an option [c/r/s/e]: " choice
        case "$choice" in
            c)
                print_info "Continuing to next step..."
                return 0
                ;;
            r)
                print_info "Retrying current step..."
                return 2
                ;;
            s)
                print_info "Opening a shell. Type 'exit' to return to the installer."
                /bin/bash
                print_info "Returned from shell. Retrying current step..."
                return 2
                ;;
            e|*)
                print_info "Installation aborted by user."
                exit 1
                ;;
        esac
    else
        print_info "Switching to manual mode to resolve the issue."
        MANUAL_MODE=true
        
        echo -e "Options:"
        echo -e "  ${GREEN}c${NC} - Continue to next step"
        echo -e "  ${YELLOW}r${NC} - Retry current step"
        echo -e "  ${BLUE}s${NC} - Open a shell to debug"
        echo -e "  ${RED}e${NC} - Exit installation"
        
        read -p "Select an option [c/r/s/e]: " choice
        case "$choice" in
            c)
                print_info "Continuing to next step..."
                return 0
                ;;
            r)
                print_info "Retrying current step..."
                return 2
                ;;
            s)
                print_info "Opening a shell. Type 'exit' to return to the installer."
                /bin/bash
                print_info "Returned from shell. Retrying current step..."
                return 2
                ;;
            e|*)
                print_info "Installation aborted by user."
                exit 1
                ;;
        esac
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

# Detect available disks
detect_disks() {
    local disks=()
    local disk_info=""
    
    print_info "Detecting available disks..."
    
    # Get list of disks
    while read -r disk; do
        if [[ $disk =~ ^/dev/(sd[a-z]|nvme[0-9]n[0-9]|vd[a-z])$ ]]; then
            size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            model=$(lsblk -dno MODEL "$disk" 2>/dev/null)
            disks+=("$disk")
            disk_info+="$disk: $size $model\n"
        fi
    done < <(lsblk -pno NAME | grep -E '^/dev/(sd[a-z]|nvme[0-9]n[0-9]|vd[a-z])$')
    
    if [ ${#disks[@]} -eq 0 ]; then
        print_error "No disks detected. Cannot continue."
        return 1
    fi
    
    print_info "Found ${#disks[@]} disk(s):"
    echo -e "$disk_info"
    
    if [ ${#disks[@]} -eq 1 ]; then
        DISK_DEVICE="${disks[0]}"
        print_info "Using the only available disk: $DISK_DEVICE"
    else
        echo "Select a disk to install Strix OS:"
        select disk in "${disks[@]}"; do
            if [ -n "$disk" ]; then
                DISK_DEVICE="$disk"
                print_info "Selected disk: $DISK_DEVICE"
                break
            else
                print_error "Invalid selection. Please try again."
            fi
        done
    fi
    
    # Confirm disk selection
    echo -e "${RED}WARNING: All data on $DISK_DEVICE will be erased!${NC}"
    read -p "Are you sure you want to use $DISK_DEVICE? (yes/no): " confirm
    if [[ $confirm != "yes" ]]; then
        print_info "Disk selection canceled. Please select another disk."
        DISK_DEVICE=""
        return 1
    fi
    
    return 0
}

# Check if partitions exist
check_partitions() {
    local efi_part="${DISK_DEVICE}1"
    local swap_part="${DISK_DEVICE}2"
    local root_part="${DISK_DEVICE}3"
    
    # Handle NVMe naming convention
    if [[ $DISK_DEVICE == *"nvme"* ]]; then
        efi_part="${DISK_DEVICE}p1"
        swap_part="${DISK_DEVICE}p2"
        root_part="${DISK_DEVICE}p3"
    fi
    
    print_info "Checking if partitions exist on $DISK_DEVICE"
    
    if [ ! -b "$efi_part" ]; then
        print_warning "EFI partition ($efi_part) not found"
        return 1
    fi
    
    if [ ! -b "$swap_part" ]; then
        print_warning "Swap partition ($swap_part) not found"
        return 1
    fi
    
    if [ ! -b "$root_part" ]; then
        print_warning "Root partition ($root_part) not found"
        return 1
    fi
    
    print_info "All required partitions found"
    return 0
}

# Get partition names based on device
get_partition_names() {
    if [[ $DISK_DEVICE == *"nvme"* ]]; then
        EFI_PART="${DISK_DEVICE}p1"
        SWAP_PART="${DISK_DEVICE}p2"
        ROOT_PART="${DISK_DEVICE}p3"
    else
        EFI_PART="${DISK_DEVICE}1"
        SWAP_PART="${DISK_DEVICE}2"
        ROOT_PART="${DISK_DEVICE}3"
    fi
    
    print_info "EFI: $EFI_PART, Swap: $SWAP_PART, Root: $ROOT_PART"
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

print_step "Detecting and Selecting Disk"
if confirm_step; then
    while ! detect_disks; do
        print_warning "Disk selection failed. Please try again."
    done
    
    print_info "Disk selection completed: $DISK_DEVICE will be used for installation"
    lsblk "$DISK_DEVICE" -o NAME,SIZE,TYPE,MOUNTPOINT >> "$LOG_FILE"
fi

print_step "Partitioning Disk"
if confirm_step; then
    print_info "Manual partitioning recommended for data safety"
    print_info "Create the following partitions on $DISK_DEVICE:"
    print_info "  - EFI partition (${DISK_DEVICE}1, 512MB, FAT32, EFI System)"
    print_info "  - Swap partition (${DISK_DEVICE}2, RAM size, Linux swap)"
    print_info "  - Root partition (${DISK_DEVICE}3, Remaining space, Linux filesystem)"
    
    if [ "$MANUAL_MODE" = true ]; then
        print_info "Available partitioning tools:"
        PS3="Select a partitioning tool: "
        select tool in "fdisk" "cfdisk" "parted" "skip"; do
            case $tool in
                "fdisk")
                    fdisk "$DISK_DEVICE"
                    break
                    ;;
                "cfdisk")
                    cfdisk "$DISK_DEVICE"
                    break
                    ;;
                "parted")
                    parted "$DISK_DEVICE"
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
        print_info "Using cfdisk for partitioning..."
        print_info "When cfdisk opens:"
        print_info "1. Create a 512MB EFI partition (type: EFI System)"
        print_info "2. Create a swap partition (type: Linux swap)"
        print_info "3. Create a root partition with remaining space (type: Linux filesystem)"
        print_info "4. Write changes and quit"
        read -p "Press Enter to continue to cfdisk..."
        cfdisk "$DISK_DEVICE"
    fi
    
    # Update partition variables
    get_partition_names
    
    # Verify partitions
    print_info "Verifying partitions..."
    if ! check_partitions; then
        while true; do
            print_error "Required partitions not found on $DISK_DEVICE"
            print_info "Options:"
            echo "1) Retry partitioning"
            echo "2) Manual recovery (shell)"
            echo "3) Skip verification and continue anyway (risky)"
            echo "4) Abort installation"
            read -p "Select an option [1-4]: " part_option
            
            case $part_option in
                1)
                    print_info "Restarting partitioning..."
                    if [ "$MANUAL_MODE" = true ]; then
                        PS3="Select a partitioning tool: "
                        select tool in "fdisk" "cfdisk" "parted"; do
                            case $tool in
                                "fdisk")
                                    fdisk "$DISK_DEVICE"
                                    break
                                    ;;
                                "cfdisk")
                                    cfdisk "$DISK_DEVICE"
                                    break
                                    ;;
                                "parted")
                                    parted "$DISK_DEVICE"
                                    break
                                    ;;
                                *)
                                    print_error "Invalid option"
                                    ;;
                            esac
                        done
                    else
                        cfdisk "$DISK_DEVICE"
                    fi
                    get_partition_names
                    if check_partitions; then
                        print_info "Partitioning completed successfully!"
                        break
                    fi
                    ;;
                2)
                    print_info "Opening shell for manual recovery. Type 'exit' when done."
                    /bin/bash
                    get_partition_names
                    if check_partitions; then
                        print_info "Partitions verified after manual recovery!"
                        break
                    fi
                    ;;
                3)
                    print_warning "Skipping partition verification. Installation may fail later."
                    break
                    ;;
                4)
                    print_info "Installation aborted by user."
                    exit 1
                    ;;
                *)
                    print_error "Invalid option. Please select 1-4."
                    ;;
            esac
        done
    fi
    
    # Show partition information
    print_info "Partition layout:"
    lsblk "$DISK_DEVICE" -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT >> "$LOG_FILE"
    fdisk -l "$DISK_DEVICE" >> "$LOG_FILE"
    lsblk "$DISK_DEVICE" -o NAME,SIZE,FSTYPE
fi

print_step "Formatting Partitions"
if confirm_step; then
    # Update partition variables to ensure we have the correct ones
    get_partition_names
    
    print_info "Formatting EFI partition ($EFI_PART)"
    if [ ! -b "$EFI_PART" ]; then
        print_error "EFI partition $EFI_PART doesn't exist!"
        result=$(handle_error "Failed to find EFI partition")
        if [ "$result" -eq 2 ]; then continue; fi
    else
        if ! mkfs.fat -F32 "$EFI_PART" &>> "$LOG_FILE"; then
            result=$(handle_error "Failed to format EFI partition")
            if [ "$result" -eq 2 ]; then continue; fi
        fi
    fi
    
    print_info "Formatting root partition ($ROOT_PART)"
    if [ ! -b "$ROOT_PART" ]; then
        print_error "Root partition $ROOT_PART doesn't exist!"
        result=$(handle_error "Failed to find root partition")
        if [ "$result" -eq 2 ]; then continue; fi
    else
        if ! mkfs.ext4 "$ROOT_PART" &>> "$LOG_FILE"; then
            result=$(handle_error "Failed to format root partition")
            if [ "$result" -eq 2 ]; then continue; fi
        fi
    fi
    
    print_info "Creating and activating swap ($SWAP_PART)"
    if [ ! -b "$SWAP_PART" ]; then
        print_error "Swap partition $SWAP_PART doesn't exist!"
        result=$(handle_error "Failed to find swap partition")
        if [ "$result" -eq 2 ]; then continue; fi
    else
        if ! mkswap "$SWAP_PART" &>> "$LOG_FILE"; then
            result=$(handle_error "Failed to create swap")
            if [ "$result" -eq 2 ]; then continue; fi
        fi
        
        if ! swapon "$SWAP_PART" &>> "$LOG_FILE"; then
            result=$(handle_error "Failed to activate swap")
            if [ "$result" -eq 2 ]; then continue; fi
        fi
    fi
    
    print_info "All partitions formatted successfully"
fi

print_step "Mounting Partitions"
if confirm_step; then
    print_info "Mounting root partition to /mnt"
    if [ ! -b "$ROOT_PART" ]; then
        print_error "Root partition $ROOT_PART doesn't exist!"
        result=$(handle_error "Failed to find root partition for mounting")
        if [ "$result" -eq 2 ]; then continue; fi
    else
        if ! mount "$ROOT_PART" /mnt &>> "$LOG_FILE"; then
            result=$(handle_error "Failed to mount root partition")
            if [ "$result" -eq 2 ]; then continue; fi
        fi
    fi
    
    print_info "Creating and mounting EFI directory"
    if ! mkdir -p /mnt/boot/efi &>> "$LOG_FILE"; then
        result=$(handle_error "Failed to create EFI directory")
        if [ "$result" -eq 2 ]; then continue; fi
    fi
    
    if [ ! -b "$EFI_PART" ]; then
        print_error "EFI partition $EFI_PART doesn't exist!"
        result=$(handle_error "Failed to find EFI partition for mounting")
        if [ "$result" -eq 2 ]; then continue; fi
    else
        if ! mount "$EFI_PART" /mnt/boot/efi &>> "$LOG_FILE"; then
            result=$(handle_error "Failed to mount EFI partition")
            if [ "$result" -eq 2 ]; then continue; fi
        fi
    fi
    
    print_info "All partitions mounted successfully"
    print_info "Current mount points:"
    mount | grep '/mnt' >> "$LOG_FILE"
    mount | grep '/mnt'
fi

print_step "Installing Base System"
if confirm_step; then
    print_info "This may take a while depending on your internet speed..."
    print_info "Installing essential packages (base, linux, firmware, etc.)"
    
    # Check if pacman mirrors are responsive
    if ! pacman -Sy &>> "$LOG_FILE"; then
        print_warning "Failed to synchronize pacman database. Trying to update mirrorlist..."
        if command -v reflector &> /dev/null; then
            print_info "Using reflector to update mirrors..."
            reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist &>> "$LOG_FILE"
        else
            print_warning "reflector not found. Using default mirrors."
        fi
    fi
    
    if ! pacstrap /mnt base linux linux-firmware sudo vim nano git networkmanager &>> "$LOG_FILE"; then
        result=$(handle_error "Failed to install base system")
        if [ "$result" -eq 2 ]; then 
            print_info "Retrying base system installation..."
            if ! pacstrap /mnt base linux linux-firmware &>> "$LOG_FILE"; then
                result=$(handle_error "Failed to install minimal base system")
                if [ "$result" -eq 2 ]; then continue; fi
            else
                print_info "Minimal base system installed. Installing additional packages..."
                if ! pacstrap /mnt sudo vim nano git networkmanager &>> "$LOG_FILE"; then
                    print_warning "Some additional packages failed to install but installation can continue"
                fi
            fi
        fi
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
