#!/bin/bash

. scripts/utils.sh

# Display help
display_help() {
    echo -e "Usage: ./script.sh ${C_BLUE}[bin|docker]${C_RESET} [DEST_DIR]"
    echo
    echo -e "${C_BLUE}Options:${C_RESET}"
    echo -e "  ${C_BLUE}bin${C_RESET}       - Download the latest version of the binaries. Optionally specify a destination directory, default to ~/blocc"
    echo -e "  ${C_BLUE}docker${C_RESET}    - ${C_RED}DELETE${C_RESET} related Docker images, so that ${C_YELLOW}./network.sh up${C_RESET} will pull the latest images"
    echo
    echo -e "${C_YELLOW}Examples:"
    echo -e "  ./script.sh bin"
    echo -e "  ./script.sh bin /path/to/destination"
    echo -e "  ./script.sh docker${C_RESET} "
    echo
}

# Check if help is requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    display_help
    exit 0
fi

download_binaries() {
    local dest_dir=$1

    # Detect the platform and architecture
    OS=$(uname -s)
    ARCH=$(uname -m)

    # Map the architecture and OS to the expected format
    case "$ARCH" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${C_RED}Unsupported architecture: $ARCH${C_RESET}"
            exit 1
            ;;
    esac

    case "$OS" in
        Linux)
            OS="linux"
            ;;
        Darwin)
            OS="darwin"
            ;;
        *)
            echo -e "${C_RED}Unsupported operating system: $OS${C_RESET}"
            exit 1
            ;;
    esac

    BINARY_FILE="hyperledger-fabric-${OS}-${ARCH}-2.5.1.tar.gz"
    URL="https://github.com/ImperialCollegeLondon/blocc-fabric/releases/download/latest/${BINARY_FILE}"
    echo -e "${C_BLUE}===> Downloading: ${URL}${C_RESET}"
    echo -e "${C_BLUE}===> Will unpack to: ${dest_dir}${C_RESET}"
    curl -L --retry 5 --retry-delay 3 "${URL}" | tar xz -C ${dest_dir} || rc=$?
    if [ -n "$rc" ]; then
        echo -e "${C_RED}==> There was an error downloading the binary file.${C_RESET}"
        exit 1
    else
        echo -e "${C_GREEN}==> Done.${C_RESET}"
    fi
}

# Function to delete Docker images based on a pattern
delete_images() {
    pattern=$1
    docker images | grep "$pattern" | awk '{print $3}' | xargs docker rmi
}

# Main script logic
case $1 in
    bin)
        echo -e "${C_BLUE}Downloading the latest version of the binaries...${C_RESET}"
        DEST_DIR=${2:-~/blocc}  # Default to ~/blocc if not provided
        download_binaries $DEST_DIR
        ;;
    docker)
        echo -e "${C_BLUE}Deleting related Docker images...${C_RESET}"
        delete_images "ghcr.io/imperialcollegelondon/fabric-"
        ;;
    *)
        display_help
        exit 1
        ;;
esac
