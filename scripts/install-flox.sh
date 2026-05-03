#!/usr/bin/env bash

# Install Flox without using Homebrew
# Downloads and installs the correct package for the current OS/architecture

set -e

if command -v flox &> /dev/null; then
    echo "Flox is already installed ($(flox --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "Installing Flox..."

OS=$(uname -s)
ARCH=$(uname -m)
FLOX_VERSION="1.11.4"

# Create temp directory for download
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

if [[ "$OS" == "Darwin" ]]; then
    # macOS
    if [[ "$ARCH" == "arm64" ]]; then
        PKG_URL="https://downloads.flox.dev/by-env/stable/osx/flox-${FLOX_VERSION}.aarch64-darwin.pkg"
        PKG_FILE="flox-${FLOX_VERSION}.aarch64-darwin.pkg"
    else
        PKG_URL="https://downloads.flox.dev/by-env/stable/osx/flox-${FLOX_VERSION}.x86_64-darwin.pkg"
        PKG_FILE="flox-${FLOX_VERSION}.x86_64-darwin.pkg"
    fi
    
    echo "Downloading Flox for macOS..."
    curl -fsSL -o "$PKG_FILE" "$PKG_URL"
    
    echo "Installing Flox pkg (requires sudo)..."
    sudo installer -pkg "$PKG_FILE" -target /
    
elif [[ "$OS" == "Linux" ]]; then
    # Linux - detect package manager
    if command -v dpkg &> /dev/null; then
        # Debian-based
        if [[ "$ARCH" == "aarch64" ]]; then
            DEB_URL="https://downloads.flox.dev/by-env/stable/deb/flox-${FLOX_VERSION}.aarch64-linux.deb"
            DEB_FILE="flox-${FLOX_VERSION}.aarch64-linux.deb"
        else
            DEB_URL="https://downloads.flox.dev/by-env/stable/deb/flox-${FLOX_VERSION}.x86_64-linux.deb"
            DEB_FILE="flox-${FLOX_VERSION}.x86_64-linux.deb"
        fi
        
        echo "Downloading Flox for Debian/Ubuntu..."
        curl -fsSL -o "$DEB_FILE" "$DEB_URL"
        sudo dpkg -i "$DEB_FILE" || sudo apt-get install -f -y
        
    elif command -v rpm &> /dev/null; then
        # RPM-based
        if [[ "$ARCH" == "aarch64" ]]; then
            RPM_URL="https://downloads.flox.dev/by-env/stable/rpm/flox-${FLOX_VERSION}.aarch64-linux.rpm"
            RPM_FILE="flox-${FLOX_VERSION}.aarch64-linux.rpm"
        else
            RPM_URL="https://downloads.flox.dev/by-env/stable/rpm/flox-${FLOX_VERSION}.x86_64-linux.rpm"
            RPM_FILE="flox-${FLOX_VERSION}.x86_64-linux.rpm"
        fi
        
        echo "Downloading Flox for RHEL/CentOS..."
        curl -fsSL -o "$RPM_FILE" "$RPM_URL"
        sudo rpm -ivh "$RPM_FILE" || sudo yum install -y "$RPM_FILE"
    else
        echo "Error: Unsupported Linux distribution"
        exit 1
    fi
else
    echo "Error: Unsupported operating system: $OS"
    exit 1
fi

# Cleanup
cd - > /dev/null
rm -rf "$TMP_DIR"

# Verify installation
if command -v flox &> /dev/null; then
    echo "Flox installed successfully: $(flox --version)"
else
    echo "Error: Flox installation failed"
    exit 1
fi
