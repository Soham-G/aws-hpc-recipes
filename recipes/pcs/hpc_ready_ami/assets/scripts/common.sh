#!/usr/bin/env bash

# This script update the OS and base packages for AMIs from 
# operating systems supported by AWS PCS. It is intended to 
# replace the UpdateOS ImageBuilder component with a solution
# that is more flexible to the specifics of each supported OS.
#
# Exports OS, VERSION, ARCHITECTURE variables

set -o errexit -o pipefail -o nounset

OS=""
VERSION=""
ARCHITECTURE=""

# Function to log
logger() {
   local script="$0";
   local log_message="$1";
   local log_level="${2:-INFO}";
   local timestamp=$(date +"%Y-%m-%dT%H:%M:%S.%3N%:z");
   echo "[$timestamp] - $script: $log_level: $log_message";
}

# These are stub functions. In scripts that import common.sh, we expect to find
# functions defined with the same names, one for each OS/version combination.
# 
# If the function isn't defined in the script, it will fall back to the one defined here.

handle_ubuntu_22.04() {
    logger "Default for Ubuntu 22.04" "WARNING"
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
}

handle_rhel_9() { 
    logger "Default for RHEL 9" "WARNING"
}

handle_rocky_9() {
    logger "Default for Rocky Linux 9" "WARNING"
}

handle_amzn_2() {
    logger "Default for Amazon Linux 2" "WARNING"
}

detect_os_version() {

    ARCHITECTURE=$(uname -m)

    # Detect the operating system
    if [ -f /etc/os-release ]; then
        # Read the contents of the /etc/os-release file
        # shellcheck disable=SC1091
        . /etc/os-release
        # Extract the operating system ID and version
        OS=$ID
        VERSION=$VERSION_ID
    else
        logger "Unable to detect the operating system." "ERROR"
        exit 1
    fi

    # Verify if the OS is supported
    case "$OS" in
        ubuntu)
            if [ "$VERSION" == "22.04" ]; then
                logger "Detected OS: $OS, Version: $VERSION, Architecture: $ARCHITECTURE" "INFO"
            else
                logger "Unsupported Ubuntu version: $VERSION" "ERROR"
                exit 1
            fi
            ;;
        rhel)
            if [[ "$VERSION" =~ ^9\.* ]]; then
                VERSION=9
                logger "Detected OS: $OS, Version: $VERSION, Architecture: $ARCHITECTURE" "INFO"
            else
                logger "Unsupported RHEL version: $VERSION" "ERROR" "ERROR"
                exit 1
            fi
            ;;
        rocky)
            if [[ "$VERSION" =~ ^9\.* ]]; then
                VERSION=9
                logger "Detected OS: $OS, Version: $VERSION, Architecture: $ARCHITECTURE" "INFO"
            else
                logger "Unsupported Rocky Linux version: $VERSION" "ERROR"
                exit 1
            fi
            ;;
        amzn)
            if [ "$VERSION" == "2" ]; then
                logger "Detected OS: $OS, Version: $VERSION, Architecture: $ARCHITECTURE" "INFO"
            else
                logger "Unsupported Amazon Linux version: $VERSION" "ERROR"
                exit 1
            fi
            ;;
        *)
            logger "Unsupported operating system: $OS" "ERROR"
            exit 1
            ;;
    esac

    export OS
    export VERSION
    export ARCHITECTURE

}
