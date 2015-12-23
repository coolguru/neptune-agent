#!/bin/bash

# Usage : Just run this script with root permissions
# Purpose : Installs neptune agent on a OSX machine and starts it
# Steps :
# 1) Creates a new user called "neptune" or an user specified on the command line on the host
# 2) Fetches latest and stable neptune agent binary, config file and daemon plist
# 3) Push daemon to launchd and start agent as the specified user in step 1

# Global variables
NEPTUNE_AGENT_URL="https://raw.githubusercontent.com/neptuneio/neptune-agent/prod"
NEPTUNE_AGENT="neptune-agent"
NEPTUNE_AGENT_USER="neptune"
NEPTUNE_AGENT_DIR="agent"
NEPTUNE_AGENT_PLIST="com.neptune.agent.plist"
NEPTUNE_AGENT_CONFIG="neptune-agent.json"
NEPTUNE_AGENT_LOG="neptune-agent.log"
DEFAULT_REQUIRE_SUDO="false"
NEPTUNE_END_POINT="www.neptune.io"
HOST_NAME=""
GITHUB_API_KEY=""

# Output display colors
red='\033[0;31m'
green='\033[0;32m'
NC='\033[0m' # No Color

# Set the endpoint
if [ -n "$END_POINT" ]; then
    NEPTUNE_END_POINT="$END_POINT"
    # If endpoint is specified use master version of agent
    NEPTUNE_AGENT_URL="https://raw.githubusercontent.com/neptuneio/neptune-agent/master"
fi

# If the user name is specified on commandline, use it
if [ -n "$AGENT_USER" ]; then
    NEPTUNE_AGENT_USER="$AGENT_USER"
fi
echo "Username: $NEPTUNE_AGENT_USER"

# Check if user be given sudo permissions
if [ -z "$REQUIRE_SUDO" ]; then
    REQUIRE_SUDO="$DEFAULT_REQUIRE_SUDO"
fi
echo "Sudo priveleges : $REQUIRE_SUDO"

# Check if proper API_KEY is given, else exit
if [ -z "$API_KEY" ]; then
    echo "Please give a proper API_KEY and retry installing agent."
    exit 1
fi

# Check if a hostname is assigned
if [ -n "$ASSIGNED_HOST_NAME" ]; then
    HOST_NAME=$ASSIGNED_HOST_NAME
fi

# Use curl or wget to download files
DOWNLOAD_CMD='curl -sS -o'
if which curl > /dev/null; then
    DOWNLOAD_CMD='curl -sS -o'
elif which wget > /dev/null; then
    DOWNLOAD_CMD='wget -q -O'
else
    echo 'No curl or wget found to download files ! Please install curl and rerun the command'
    exit 1
fi

# Find the linux distribution
if [ -f /etc/redhat-release ];then
    # Start with default linux distro of Redhat
    LINUX_DISTRIBUTION="Redhat"
else
    LINUX_DISTRIBUTION=$(grep -Eo "(Debian|Ubuntu|CentOS|SUSE|Amazon)" /etc/issue 2>/dev/null)
fi

# Find the linux host architecture
UNAME=`uname -sp | awk '{print tolower($0)}'`

if [[ ($UNAME == *"mac os x"*) || ($UNAME == *darwin*) ]]; then
    PLATFORM="darwin"
elif [[ ($UNAME == *"freebsd"*) ]]; then
    PLATFORM="freebsd"
    echo "Please use a freebsd installation script"
    exit 1
else
    PLATFORM="linux"
    echo "Please use a linux installation script"
    exit 1
fi

case $UNAME in
    *x86_64*) ARCH="amd64" ;;
    *arm*)    ARCH="arm"   ;;
    *)        ARCH="386"   ;;
esac


# Start install of agent
echo "Installing Neptune agent on $PLATFORM for $ARCH ..."

# Unload any existing neptune plist jobs
if [ -e  /Library/LaunchDaemons/$NEPTUNE_AGENT_PLIST ]; then
    sudo launchctl unload -w /Library/LaunchDaemons/$NEPTUNE_AGENT_PLIST
    sleep 3;
fi

# Create the new user if it does not exist
sudo id -u $NEPTUNE_AGENT_USER &>/dev/null
if [ $? -ne 0 ]; then
    sudo dscl . -create /Users/$NEPTUNE_AGENT_USER
    sudo dscl . -create /Users/$NEPTUNE_AGENT_USER UserShell /bin/bash
    sudo dscl . -create /Users/$NEPTUNE_AGENT_USER RealName "Neptune agent"
    LAST_ID=`sudo dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1`
    NEXT_ID=$((LAST_ID + 1))
    sudo dscl . -create /Users/$NEPTUNE_AGENT_USER UniqueID $NEXT_ID
    sudo dscl . -create /Users/$NEPTUNE_AGENT_USER PrimaryGroupID 20
    sudo dscl . -create /Users/$NEPTUNE_AGENT_USER NFSHomeDirectory /Users/$NEPTUNE_AGENT_USER
    sudo createhomedir -u $NEPTUNE_AGENT_USER 2>&1 | grep -v "shell-init"
fi

# A Global variable but can be created only after creation of the user
NEPTUNE_AGENT_HOME=`eval echo ~$NEPTUNE_AGENT_USER/$NEPTUNE_AGENT_DIR`
echo "Home dir: $NEPTUNE_AGENT_HOME"
sleep 2

# Create Neptune agent directory in user's home
sudo mkdir -p $NEPTUNE_AGENT_HOME
sleep 2

# Fetch the latest stable neptune agent and plist
echo "Fetching the latest version of neptune agent and plist"
sudo $DOWNLOAD_CMD $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz $NEPTUNE_AGENT_URL/downloads/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz
sudo $DOWNLOAD_CMD $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_PLIST $NEPTUNE_AGENT_URL/scripts/$PLATFORM/$NEPTUNE_AGENT_PLIST
sudo tar -zxf $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz -C $NEPTUNE_AGENT_HOME

# Remove tar file if unzip is successful
if [ $? -eq 0 ]; then
    sudo rm -rf $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz
fi

# Update repo URL in the daemon to enable agent updates
sudo sed -i.bak "s|AGENT_USER_HERE|$NEPTUNE_AGENT_USER|; s|AGENT_PATH_HERE|$NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT| ; s|WORKING_DIRECTORY_HERE|$NEPTUNE_AGENT_HOME|" $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_PLIST
sleep 1
sudo rm -f $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT_PLIST}.bak

# Populate the neptune config
echo "Updating agent config"
sudo sed -i.bak "s|API_KEY_HERE|$API_KEY|; s|END_POINT_HERE|$NEPTUNE_END_POINT|; s|AGENT_LOG_HERE|$NEPTUNE_AGENT_LOG|; s|ASSIGNED_HOSTNAME_HERE|$HOST_NAME|; s|GITHUB_KEY_HERE|$GITHUB_API_KEY|" $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_CONFIG
sudo rm -f $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT_CONFIG}.bak

# Add neptune agent user to sudoers list and turn off requiretty
if [ "$REQUIRE_SUDO" == "true" ] || [ "$REQUIRE_SUDO" == "TRUE" ] || [ "$REQUIRE_SUDO" == "True" ]; then
    # When /etc/sudoers.d exists, add a local file instead of modifying /etc/sudoers directly
    if [ -d "/etc/sudoers.d" ]; then
        echo "Adding $NEPTUNE_AGENT_USER to sudoers list without tty requirement"

        if [ ! -f /etc/sudoers.d/neptune_sudo_perms ]; then
            sudo echo "$NEPTUNE_AGENT_USER ALL=(ALL) NOPASSWD:ALL
            Defaults:$NEPTUNE_AGENT_USER !requiretty
            " > /tmp/sudoers.bak

            # Check the syntax of the backup file to make sure it is correct.
            sudo visudo -cf /tmp/sudoers.bak
            if [ $? -eq 0 ]; then
                # Place the new sudoers file as local sudoers file if syntax is correct.
                sudo cp /tmp/sudoers.bak /etc/sudoers.d/neptune_sudo_perms
            else
                echo "Couldn't add $NEPTUNE_AGENT_USER to sudoers list programmatically"
                echo "Please give sudo permission manually by following instructions at http://docs.neptune.io/docs/sudo-priveleges-control"
            fi
        fi
    else
        echo "Couldn't add $NEPTUNE_AGENT_USER to sudoers list programmatically as your host doesn't have /etc/sudoers.d directory to safely add sudo permissions"
        echo "Please give sudo permission manually by following instructions at http://docs.neptune.io/docs/sudo-priveleges-control"
    fi
fi

# Add exec permissions to neptune agent, plist and config file
sudo chmod 755 $NEPTUNE_AGENT_HOME $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_PLIST $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_CONFIG

# Make the user as owner of the neptune agent home directory
sudo chown -R $NEPTUNE_AGENT_USER $NEPTUNE_AGENT_HOME

# For OSX use launchctl to run it as a service
# Fetch agent plist
sudo cp $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_PLIST /Library/LaunchDaemons

# Start the agent by loading the plist
echo "Starting Neptune agent..."
sudo launchctl load -w /Library/LaunchDaemons/$NEPTUNE_AGENT_PLIST
# Check the status of daemon after 2 sec
sleep 2;
sudo launchctl list |grep neptune

echo "-------------------------------------"
echo "To check agent status run  : sudo launchctl list |grep neptune"
echo "To stop agent run          : sudo launchctl unload -w /Library/LaunchDaemons/$NEPTUNE_AGENT_PLIST"
echo "To start agent run         : sudo launchctl load -w /Library/LaunchDaemons/$NEPTUNE_AGENT_PLIST"
echo "Agent log available at     : $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_LOG"
