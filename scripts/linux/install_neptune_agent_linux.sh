#!/bin/bash

# Usage : Just run this script with root permissions
# Purpose : Installs neptune agent on a linux machine and starts it
# Steps :
# 1) Creates a new user called "neptuneagent" or an user specified on the command line on the host
# 2) Fetches latest and stable neptune agent binary, config file and daemon
# 3) Push daemon to init.d (Currently supports sysV based init only)
# 4) Starts the agent as the specified user in step 1

# Global variables
NEPTUNE_AGENT_URL="https://raw.githubusercontent.com/neptuneio/neptune-agent/prod"
NEPTUNE_AGENT="neptune-agent"
NEPTUNE_AGENT_USER="neptuneio"
NEPTUNE_AGENT_DIR="agent"
NEPTUNE_AGENT_DAEMON="neptune-agentd"
NEPTUNE_AGENT_CONFIG="neptune-agent.json"
NEPTUNE_AGENT_LOG="neptune-agent.log"
DEFAULT_REQUIRE_SUDO="false"
NEPTUNE_END_POINT="www.neptune.io"

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
    echo "Please use mac or OSX installation script"
    exit 1
elif [[ ($UNAME == *"freebsd"*) ]]; then
    PLATFORM="freebsd"
else
    PLATFORM="linux"
fi

case $UNAME in
    *x86_64*) ARCH="amd64" ;;
    *arm*)    ARCH="arm"   ;;
    *)        ARCH="386"   ;;
esac


# Start install of agent
echo "Installing Neptune agent on $PLATFORM for $ARCH ..."

# Remove existing agents if any
if [ -e /etc/init.d/$NEPTUNE_AGENT_DAEMON ]; then
    sudo service $NEPTUNE_AGENT_DAEMON uninstall
fi
sleep 2

# Create the new user if it does not exist
sudo id -u $NEPTUNE_AGENT_USER &>/dev/null || sudo useradd $NEPTUNE_AGENT_USER -m

# A Global variable but can be created only after creation of the user
NEPTUNE_AGENT_HOME=`eval echo ~$NEPTUNE_AGENT_USER/$NEPTUNE_AGENT_DIR`
echo "Home dir: $NEPTUNE_AGENT_HOME"
sleep 2

# Create Neptune agent directory in user's home
sudo mkdir -p $NEPTUNE_AGENT_HOME
sleep 2

# Fetch the latest stable neptune agent and neptune agent daemon
echo "Fetching the latest version of neptune agent and daemon"
sudo $DOWNLOAD_CMD $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz $NEPTUNE_AGENT_URL/downloads/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz
sudo $DOWNLOAD_CMD $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_DAEMON $NEPTUNE_AGENT_URL/scripts/$PLATFORM/$NEPTUNE_AGENT_DAEMON
sudo tar -zxf $NEPTUNE_AGENT_HOME/${NEPTUNE_AGENT}-${PLATFORM}-${ARCH}.tar.gz -C $NEPTUNE_AGENT_HOME

# Update repo URL in the daemon to enable agent updates
sudo sed -i "s|AGENT_USER_HERE|$NEPTUNE_AGENT_USER|" $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_DAEMON

# Populate the neptuneio config
echo "Updating agent config"
sudo sed -i "s|API_KEY_HERE|$API_KEY|" $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_CONFIG
sudo sed -i "s|END_POINT_HERE|$NEPTUNE_END_POINT|" $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_CONFIG
sudo sed -i "s|AGENT_LOG_HERE|$NEPTUNE_AGENT_LOG|" $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_CONFIG

# Add neptuneioagent user to sudoers list and turn off requiretty
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
    fi
fi

# Add exec permissions to neptune agent and daemon
sudo chmod 755 $NEPTUNE_AGENT_HOME $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_DAEMON $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_CONFIG

# Make the user as owner of the neptune agent home directory
sudo chown -R $NEPTUNE_AGENT_USER $NEPTUNE_AGENT_HOME

# Copy neptune agent daemon to init.d directory
sudo cp $NEPTUNE_AGENT_HOME/$NEPTUNE_AGENT_DAEMON /etc/init.d/

# Based on linux distribution use chkconfig or update-rc.d

if [ "$LINUX_DISTRIBUTION" == "Amazon" -o "$LINUX_DISTRIBUTION" == "Redhat" -o "$LINUX_DISTRIBUTION" == "CentOS" -o "$LINUX_DISTRIBUTION" == "SUSE" ]; then
    sudo chkconfig --add  $NEPTUNE_AGENT_DAEMON
    sudo chkconfig $NEPTUNE_AGENT_DAEMON on
else
    sudo update-rc.d $NEPTUNE_AGENT_DAEMON start 90 1 2 3 5 . stop 10 0 6 .
fi

# Start the agent daemon immediately ; If running, restart
sudo service $NEPTUNE_AGENT_DAEMON restart
