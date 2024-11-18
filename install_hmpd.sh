#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error counter
ERRORS=0

# Function to print headers
print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# Function to check command status
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        ERRORS=$((ERRORS + 1))
        if [ "$2" = "critical" ]; then
            echo "Critical error encountered. Exiting installation."
            exit 1
        fi
    fi
}

# Function to backup a file if it exists
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.backup_$(date +%Y%m%d_%H%M%S)"
        check_status "Backing up $1"
    fi
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Get real username (even when running with sudo)
REAL_USER=$(logname)
if [ -z "$REAL_USER" ]; then
    REAL_USER=$(who | awk 'NR==1{print $1}')
fi

print_header "Starting HMPD Installation"

# Create required directories
print_header "Creating Directories"
mkdir -p /home/$REAL_USER/Howard
mkdir -p /home/Howard
check_status "Created Howard directories"

# Update package list
print_header "Updating System"
apt update
check_status "System update" "critical"

# Install required packages
print_header "Installing Required Packages"
apt install -y curl lpctools samba
check_status "Package installation" "critical"

# Download required files from repository
print_header "Downloading Installation Files"
cd /home/$REAL_USER/Howard

FILES=(
    "EZConfig.xml"
    "hmed-hid.rules"
    "hmpd"
    "hmpd.service"
    "install_hmpd_files.sh"
    "openssl.cnf"
    "smb.conf"
    "verify.sh"
)

REPO_URL="https://raw.githubusercontent.com/jmartin-med/hmedRpi4Code/main"

for file in "${FILES[@]}"; do
    curl -LO "$REPO_URL/$file"
    check_status "Downloading $file"
done

# Set correct permissions
chmod +x install_hmpd_files.sh verify.sh
check_status "Setting script permissions"

# Install libssl1.1
print_header "Installing libssl1.1"
wget http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.1_1.1.1n-0+deb10u6_armhf.deb
check_status "Downloading libssl1.1"
dpkg -i libssl1.1_1.1.1n-0+deb10u6_armhf.deb
check_status "Installing libssl1.1"

# Backup existing configuration files
print_header "Backing Up Existing Configurations"
backup_file "/etc/udev/rules.d/hmed-hid.rules"
backup_file "/etc/systemd/system/hmpd.service"
backup_file "/etc/ssl/openssl.cnf"
backup_file "/etc/samba/smb.conf"

# Copy files to system locations
print_header "Installing System Files"
cp hmpd /usr/bin/
chmod +x /usr/bin/hmpd
cp hmed-hid.rules /etc/udev/rules.d/
cp hmpd.service /etc/systemd/system/
cp openssl.cnf /etc/ssl/
cp smb.conf /etc/samba/
cp EZConfig.xml /home/Howard/
cp EZConfig.xml /home/$REAL_USER/Howard/
check_status "Copying system files"

# Set correct permissions for EZConfig
chmod 644 /home/Howard/EZConfig.xml
chown $REAL_USER:$REAL_USER /home/Howard/EZConfig.xml
chmod 644 /home/$REAL_USER/Howard/EZConfig.xml
chown $REAL_USER:$REAL_USER /home/$REAL_USER/Howard/EZConfig.xml
check_status "Setting EZConfig permissions"

# Configure Samba
print_header "Configuring Samba"
systemctl restart smbd
check_status "Restarting Samba service"
echo -e "${YELLOW}Please set a Samba password for user $REAL_USER${NC}"
smbpasswd -a $REAL_USER

# Add user to dialout group
print_header "Configuring User Permissions"
usermod -a -G dialout $REAL_USER
check_status "Adding user to dialout group"

# Reload udev rules
print_header "Configuring USB Devices"
udevadm control --reload-rules
udevadm trigger
check_status "Reloading udev rules"

# Configure and start service
print_header "Configuring HMPD Service"
systemctl daemon-reload
systemctl start hmpd.service
check_status "Starting HMPD service"
systemctl enable hmpd.service
check_status "Enabling HMPD service"

# Run verification script
print_header "Running System Verification"
cd /home/$REAL_USER/Howard
./verify.sh

print_header "Installation Complete"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "\nPlease:"
    echo "1. Edit /home/Howard/EZConfig.xml with your network settings"
    echo "2. Edit /home/$REAL_USER/Howard/EZConfig.xml with the same settings"
    echo "3. Reconnect USB devices"
    echo "4. Reboot the system"
    echo -e "\nAfter reboot, run: sudo /home/$REAL_USER/Howard/verify.sh"
else
    echo -e "${RED}Installation completed with $ERRORS errors.${NC}"
    echo "Please check the output above for details."
fi
