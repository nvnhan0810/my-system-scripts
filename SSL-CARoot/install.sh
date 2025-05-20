#!/bin/bash

# Script to install a CA Root certificate into system trust stores
# Works on: Linux (Debian/Ubuntu, RHEL/CentOS, Fedora), macOS, Windows (requires admin PowerShell)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 -c CERTIFICATE_FILE [-k PRIVATE_KEY_FILE] [-f]"
    echo
    echo "Options:"
    echo "  -c CERTIFICATE_FILE    Path to the CA root certificate PEM file"
    echo "  -k PRIVATE_KEY_FILE    Path to the private key PEM file (optional)"
    echo "  -f                     Also install to Firefox certificate store (if Firefox is installed)"
    echo "  -h                     Display this help message"
    exit 1
}

# Parse command line arguments
while getopts "c:k:fh" opt; do
    case ${opt} in
        c )
            CERT_FILE=$OPTARG
            ;;
        k )
            KEY_FILE=$OPTARG
            ;;
        f )
            INSTALL_FIREFOX=true
            ;;
        h )
            usage
            ;;
        \? )
            echo -e "${RED}Invalid option: $OPTARG${NC}" 1>&2
            usage
            ;;
        : )
            echo -e "${RED}Invalid option: $OPTARG requires an argument${NC}" 1>&2
            usage
            ;;
    esac
done

# Check if certificate file is provided
if [ -z "$CERT_FILE" ]; then
    echo -e "${RED}Error: Certificate file is required${NC}"
    usage
fi

# Check if certificate file exists
if [ ! -f "$CERT_FILE" ]; then
    echo -e "${RED}Error: Certificate file '$CERT_FILE' not found${NC}"
    exit 1
fi

# If private key is provided, check if it exists
if [ ! -z "$KEY_FILE" ] && [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}Error: Private key file '$KEY_FILE' not found${NC}"
    exit 1
fi

# Function to detect OS
detect_os() {
    if [ "$(uname)" == "Darwin" ]; then
        echo "macos"
    elif [ "$(uname)" == "Linux" ]; then
        if [ -f /etc/debian_version ]; then
            echo "debian"
        elif [ -f /etc/redhat-release ]; then
            echo "redhat"
        elif [ -f /etc/fedora-release ]; then
            echo "fedora"
        else
            echo "linux-other"
        fi
    elif [ "$(uname -s | cut -c 1-5)" == "MINGW" ] || [ "$(uname -s | cut -c 1-5)" == "MSYS_" ]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Get certificate info for better naming
get_cert_subject_cn() {
    openssl x509 -noout -subject -in "$CERT_FILE" | grep -o "CN=.*" | sed 's/CN=//' | sed 's/,.*//' | tr -d ' '
}

# Install certificate on Debian/Ubuntu based systems
install_debian() {
    CERT_DIR="/usr/local/share/ca-certificates"
    CERT_NAME=$(get_cert_subject_cn)
    CERT_DEST="$CERT_DIR/${CERT_NAME}.crt"
    
    echo -e "${YELLOW}Installing certificate to $CERT_DEST${NC}"
    
    # Check for sudo privileges
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Requesting sudo privileges to install certificate...${NC}"
        sudo mkdir -p "$CERT_DIR"
        sudo cp "$CERT_FILE" "$CERT_DEST"
        sudo update-ca-certificates
    else
        mkdir -p "$CERT_DIR"
        cp "$CERT_FILE" "$CERT_DEST"
        update-ca-certificates
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Certificate successfully installed!${NC}"
    else
        echo -e "${RED}Failed to install certificate${NC}"
        exit 1
    fi
}

# Install certificate on RedHat/CentOS based systems
install_redhat() {
    CERT_DIR="/etc/pki/ca-trust/source/anchors"
    CERT_NAME=$(get_cert_subject_cn)
    CERT_DEST="$CERT_DIR/${CERT_NAME}.pem"
    
    echo -e "${YELLOW}Installing certificate to $CERT_DEST${NC}"
    
    # Check for sudo privileges
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Requesting sudo privileges to install certificate...${NC}"
        sudo mkdir -p "$CERT_DIR"
        sudo cp "$CERT_FILE" "$CERT_DEST"
        sudo update-ca-trust extract
    else
        mkdir -p "$CERT_DIR"
        cp "$CERT_FILE" "$CERT_DEST"
        update-ca-trust extract
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Certificate successfully installed!${NC}"
    else
        echo -e "${RED}Failed to install certificate${NC}"
        exit 1
    fi
}

# Install certificate on Fedora
install_fedora() {
    # Fedora uses the same approach as RedHat/CentOS
    install_redhat
}

# Install certificate on macOS
install_macos() {
    CERT_NAME=$(get_cert_subject_cn)
    
    echo -e "${YELLOW}Installing certificate to macOS Keychain...${NC}"
    
    # Add to system keychain
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Certificate successfully installed to System Keychain!${NC}"
    else
        echo -e "${RED}Failed to install certificate to System Keychain${NC}"
        exit 1
    fi
    
    # Also add to user keychain for completeness
    security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain "$CERT_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Certificate also installed to User Keychain!${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to install certificate to User Keychain${NC}"
    fi
}

# Install certificate on Windows (creates a PowerShell script)
install_windows() {
    CERT_NAME=$(get_cert_subject_cn)
    PS_SCRIPT="install_cert_windows.ps1"
    
    echo -e "${YELLOW}Creating PowerShell script to install certificate...${NC}"
    
    # Create PowerShell script
    cat > "$PS_SCRIPT" << EOF
# PowerShell script to install CA certificate to Windows Certificate Store
# Requires Administrator privileges

# Import certificate to Trusted Root Certification Authorities
\$certFile = "$CERT_FILE"
\$certName = "$CERT_NAME"

Write-Host "Installing certificate '\$certName' to Trusted Root Certification Authorities..."

try {
    Import-Certificate -FilePath \$certFile -CertStoreLocation Cert:\\LocalMachine\\Root
    Write-Host "Certificate successfully installed!"
} catch {
    Write-Host "Error installing certificate: \$_"
    exit 1
}
EOF
    
    echo -e "${GREEN}PowerShell script created: $PS_SCRIPT${NC}"
    echo -e "${YELLOW}To install the certificate, run the following command as Administrator:${NC}"
    echo -e "${YELLOW}powershell -ExecutionPolicy Bypass -File $PS_SCRIPT${NC}"
}

# Install for other Linux distributions
install_linux_other() {
    echo -e "${YELLOW}Unknown Linux distribution. Trying generic approach...${NC}"
    
    # Try to detect OpenSSL directory
    if [ -d "/etc/ssl/certs" ]; then
        CERT_DIR="/etc/ssl/certs"
        CERT_NAME=$(get_cert_subject_cn)
        CERT_DEST="$CERT_DIR/${CERT_NAME}.pem"
        
        echo -e "${YELLOW}Installing certificate to $CERT_DEST${NC}"
        
        # Check for sudo privileges
        if [ "$EUID" -ne 0 ]; then
            echo -e "${YELLOW}Requesting sudo privileges to install certificate...${NC}"
            sudo cp "$CERT_FILE" "$CERT_DEST"
            sudo ln -sf "$CERT_DEST" "$CERT_DIR/$(openssl x509 -hash -noout -in "$CERT_FILE").0"
        else
            cp "$CERT_FILE" "$CERT_DEST"
            ln -sf "$CERT_DEST" "$CERT_DIR/$(openssl x509 -hash -noout -in "$CERT_FILE").0"
        fi
        
        echo -e "${GREEN}Certificate installed. You may need to update your system's CA store manually.${NC}"
        echo -e "${YELLOW}For browsers like Firefox that maintain their own certificate stores,${NC}"
        echo -e "${YELLOW}you may need to import the certificate separately.${NC}"
    else
        echo -e "${RED}Could not find a suitable certificate directory.${NC}"
        echo -e "${YELLOW}Please manually install the certificate for your specific Linux distribution.${NC}"
        exit 1
    fi
}

# Function to install certificate in Firefox
install_firefox() {
    echo -e "${YELLOW}Looking for Firefox profiles...${NC}"
    
    FIREFOX_PROFILES_DIR=""
    
    # Detect OS and set Firefox profiles directory
    if [ "$(uname)" == "Darwin" ]; then
        # macOS
        FIREFOX_PROFILES_DIR="$HOME/Library/Application Support/Firefox/Profiles"
    elif [ "$(uname)" == "Linux" ]; then
        # Linux
        FIREFOX_PROFILES_DIR="$HOME/.mozilla/firefox"
    elif [ "$(uname -s | cut -c 1-5)" == "MINGW" ] || [ "$(uname -s | cut -c 1-5)" == "MSYS_" ]; then
        # Windows (Git Bash / MSYS2)
        FIREFOX_PROFILES_DIR="$APPDATA/Mozilla/Firefox/Profiles"
    else
        echo -e "${RED}Cannot detect Firefox profiles directory for this OS.${NC}"
        return 1
    fi
    
    # Check if Firefox profiles directory exists
    if [ ! -d "$FIREFOX_PROFILES_DIR" ]; then
        echo -e "${RED}Firefox profiles directory not found: $FIREFOX_PROFILES_DIR${NC}"
        echo -e "${RED}Firefox may not be installed or has not been run yet.${NC}"
        return 1
    fi
    
    # Find all profiles
    PROFILE_DIRS=$(find "$FIREFOX_PROFILES_DIR" -maxdepth 1 -type d -name "*.default*" -o -name "*.normal*")
    
    if [ -z "$PROFILE_DIRS" ]; then
        echo -e "${RED}No Firefox profiles found.${NC}"
        return 1
    fi
    
    CERT_NAME=$(get_cert_subject_cn)
    CERT_INSTALLED=false
    
    for PROFILE_DIR in $PROFILE_DIRS; do
        echo -e "${YELLOW}Installing certificate to Firefox profile: $PROFILE_DIR${NC}"
        
        # Create the cert DB directory if it doesn't exist
        mkdir -p "$PROFILE_DIR/cert9.db"
        
        # Check if certutil is available
        if command -v certutil >/dev/null 2>&1; then
            # Use certutil to import the certificate
            certutil -A -n "$CERT_NAME" -t "C,," -i "$CERT_FILE" -d "sql:$PROFILE_DIR"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Certificate successfully installed to Firefox profile!${NC}"
                CERT_INSTALLED=true
            else
                echo -e "${RED}Failed to install certificate to Firefox profile using certutil.${NC}"
            fi
        else
            # Create a Firefox certificate installer script
            FF_SCRIPT_DIR="$(dirname "$CERT_FILE")/firefox_cert_installer"
            mkdir -p "$FF_SCRIPT_DIR"
            
            # Create a simple HTML file that will help the user import the certificate
            cat > "$FF_SCRIPT_DIR/install_cert.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Firefox Certificate Installer</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            line-height: 1.6;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            border: 1px solid #ddd;
            padding: 20px;
            border-radius: 5px;
        }
        h1 {
            color: #333;
        }
        .steps {
            margin-top: 20px;
        }
        .step {
            margin-bottom: 15px;
        }
        code {
            background-color: #f4f4f4;
            padding: 2px 5px;
            border-radius: 3px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Firefox Certificate Installation</h1>
        <p>Since <code>certutil</code> is not available on your system, please follow these steps to manually install the CA root certificate in Firefox:</p>
        
        <div class="steps">
            <div class="step">1. Open Firefox and navigate to <code>about:preferences#privacy</code></div>
            <div class="step">2. Scroll down to the "Certificates" section and click on "View Certificates"</div>
            <div class="step">3. Go to the "Authorities" tab</div>
            <div class="step">4. Click on "Import" and browse to this location: <code>$CERT_FILE</code></div>
            <div class="step">5. In the dialog that appears, check "Trust this CA to identify websites" and click "OK"</div>
            <div class="step">6. Click "OK" to close the certificate manager</div>
        </div>
        
        <p>Once you've completed these steps, the certificate will be installed in Firefox.</p>
    </div>
</body>
</html>
EOF

            # Create symbolic link to certificate in the script directory
            CERT_FILENAME=$(basename "$CERT_FILE")
            ln -sf "$CERT_FILE" "$FF_SCRIPT_DIR/$CERT_FILENAME"
            
            echo -e "${YELLOW}certutil not found. Manual installation required.${NC}"
            echo -e "${YELLOW}Created Firefox certificate installation guide at:${NC}"
            echo -e "${GREEN}$FF_SCRIPT_DIR/install_cert.html${NC}"
            echo -e "${YELLOW}Open this file in a web browser for instructions.${NC}"
        fi
    done
    
    if [ "$CERT_INSTALLED" = false ]; then
        echo -e "${YELLOW}Note: For Firefox to recognize the new certificate, you may need to restart the browser.${NC}"
    fi
    
    return 0
}

# Main execution
OS=$(detect_os)
echo -e "${YELLOW}Detected OS: $OS${NC}"

case "$OS" in
    debian)
        install_debian
        ;;
    redhat)
        install_redhat
        ;;
    fedora)
        install_fedora
        ;;
    macos)
        install_macos
        ;;
    windows)
        install_windows
        ;;
    linux-other)
        install_linux_other
        ;;
    unknown)
        echo -e "${RED}Unsupported operating system. Cannot automatically install certificate.${NC}"
        exit 1
        ;;
esac

# Install to Firefox if requested
if [ "$INSTALL_FIREFOX" = true ]; then
    echo -e "${YELLOW}Installing certificate to Firefox...${NC}"
    install_firefox
fi

exit 0