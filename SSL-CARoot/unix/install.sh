#!/bin/bash

# Script to install CA Root Certificate into Trust Store
# Supports: macOS, Linux (Debian/Ubuntu, RHEL/CentOS, Fedora), and Firefox

set -e

# Check input parameters
if [ $# -lt 1 ]; then
    echo "Usage: $0 <path_to_ca_file.pem>"
    exit 1
fi

CA_FILE="$1"
CA_NAME=$(basename "$CA_FILE" .pem)

# Check if file exists
if [ ! -f "$CA_FILE" ]; then
    echo "Error: File '$CA_FILE' does not exist!"
    exit 1
fi

echo "===== Starting CA Root Certificate Installation: $CA_NAME ====="

# Determine operating system
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
    # Determine Linux distro
    if [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/redhat-release ]; then
        DISTRO="redhat"
    elif [ -f /etc/fedora-release ]; then
        DISTRO="fedora"
    else
        DISTRO="unknown"
    fi
else
    echo "Unsupported operating system: $OSTYPE"
    exit 1
fi

echo "Detected operating system: $OS_TYPE"
if [ "$OS_TYPE" == "linux" ]; then
    echo "Linux distribution: $DISTRO"
fi

# Install for macOS
install_macos() {
    echo "Installing CA Root Certificate for macOS..."
    
    # Copy cert to temp directory
    TEMP_CERT="/tmp/$CA_NAME.pem"
    cp "$CA_FILE" "$TEMP_CERT"
    
    # Add to Keychain
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$TEMP_CERT"
    
    # Update trust store
    sudo /usr/bin/update-ca-certificates 2>/dev/null || true
    
    echo "✅ CA Root Certificate installed to macOS Trust Store"
}

# Install for Debian/Ubuntu
install_debian() {
    echo "Installing CA Root Certificate for Debian/Ubuntu..."
    
    # Ensure directory exists
    sudo mkdir -p /usr/local/share/ca-certificates
    
    # Copy cert with .crt extension
    sudo cp "$CA_FILE" "/usr/local/share/ca-certificates/$CA_NAME.crt"
    
    # Update trust store
    sudo update-ca-certificates
    
    echo "✅ CA Root Certificate installed to Debian/Ubuntu Trust Store"
}

# Install for RHEL/CentOS
install_redhat() {
    echo "Installing CA Root Certificate for RHEL/CentOS..."
    
    # Ensure directory exists
    sudo mkdir -p /etc/pki/ca-trust/source/anchors/
    
    # Copy cert
    sudo cp "$CA_FILE" "/etc/pki/ca-trust/source/anchors/$CA_NAME.pem"
    
    # Update trust store
    sudo update-ca-trust extract
    
    echo "✅ CA Root Certificate installed to RHEL/CentOS Trust Store"
}

# Install for Fedora
install_fedora() {
    echo "Installing CA Root Certificate for Fedora..."
    
    # Install similar to RHEL
    install_redhat
    
    echo "✅ CA Root Certificate installed to Fedora Trust Store"
}

# Find Firefox profiles directory
find_firefox_profiles() {
    local profiles_dir=""
    
    case "$OS_TYPE" in
        "macos")
            profiles_dir="$HOME/Library/Application Support/Firefox/Profiles"
            ;;
        "linux")
            profiles_dir="$HOME/.mozilla/firefox"
            ;;
    esac
    
    echo "$profiles_dir"
}

# Install for Firefox (all OS)
install_firefox() {
    echo "Installing CA Root Certificate for Firefox..."
    
    PROFILES_DIR=$(find_firefox_profiles)
    
    if [ ! -d "$PROFILES_DIR" ]; then
        echo "⚠️ Firefox profiles directory not found. Firefox may not be installed."
        return
    fi
    
    # Find all profiles in directory
    PROFILES=$(find "$PROFILES_DIR" -maxdepth 1 -type d -name "*.default*" -o -name "*.normal*")
    
    if [ -z "$PROFILES" ]; then
        echo "⚠️ No Firefox profiles found."
        return
    fi
    
    # Variable to track if installed to at least one profile
    INSTALLED=false
    
    # Process each profile
    for PROFILE in $PROFILES; do
        echo "Processing Firefox profile: $PROFILE"
        
        # Create NSS directory if it doesn't exist
        mkdir -p "$PROFILE/security/cert9.db"
        
        # Create NSS certificate store if it doesn't exist
        if [ ! -f "$PROFILE/cert9.db" ]; then
            echo "Creating new NSS certificate database..."
            certutil -N --empty-password -d "sql:$PROFILE"
        fi
        
        # Add CA certificate to certificate store
        certutil -A -n "$CA_NAME" -t "C,," -i "$CA_FILE" -d "sql:$PROFILE"
        
        echo "✅ CA Root Certificate installed to Firefox profile: $PROFILE"
        INSTALLED=true
    done

    if [ "$INSTALLED" = true ]; then
        echo "✅ CA Root Certificate installation for Firefox completed"
    else
        echo "⚠️ Unable to install CA Root Certificate for Firefox"
    fi
}

# Check certutil for Firefox
check_certutil() {
    if ! command -v certutil &> /dev/null; then
        echo "⚠️ Tool 'certutil' not found, required for Firefox installation."
        
        # Install certutil
        if [ "$OS_TYPE" == "macos" ]; then
            echo "Installing certutil via brew..."
            if ! command -v brew &> /dev/null; then
                echo "❌ Homebrew not installed. Please install Homebrew first."
                return 1
            fi
            brew install nss
        elif [ "$OS_TYPE" == "linux" ]; then
            echo "Installing certutil..."
            if [ "$DISTRO" == "debian" ]; then
                sudo apt-get update
                sudo apt-get install -y libnss3-tools
            elif [ "$DISTRO" == "redhat" ] || [ "$DISTRO" == "fedora" ]; then
                sudo yum install -y nss-tools
            else
                echo "❌ Cannot automatically install certutil for this Linux distribution."
                return 1
            fi
        fi
        
        # Check again after installation
        if ! command -v certutil &> /dev/null; then
            echo "❌ Failed to install certutil. Firefox CA will not be installed."
            return 1
        fi
    fi
    
    return 0
}

# Run installation functions based on operating system
case "$OS_TYPE" in
    "macos")
        install_macos
        ;;
    "linux")
        case "$DISTRO" in
            "debian")
                install_debian
                ;;
            "redhat")
                install_redhat
                ;;
            "fedora")
                install_fedora
                ;;
            *)
                echo "❌ Unsupported Linux distribution: $DISTRO"
                exit 1
                ;;
        esac
        ;;
esac

# Install for Firefox (if certutil is available)
if check_certutil; then
    install_firefox
else
    echo "⚠️ Skipping Firefox installation due to missing certutil"
fi

echo "===== CA Root Certificate Installation Completed ====="
echo "Note: You may need to restart Firefox browser or your system for changes to take effect."