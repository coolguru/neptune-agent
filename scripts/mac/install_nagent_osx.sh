#!/bin/bash

# Usage : Just run this script with root permissions
# Purpose : Install neptune agent and start it
# Steps :
# 1) Install dependencies including checking if python 2.6 is installed
# 2) Create an user for the agent to run as
# 3) Fetch latest and stable neptune agent (nagent.py)
# 4) Fetch agent plist to launch it as a service in OSX
# 5) Immediately start the agent as a particular user

# Global variables
NEPTUNEIO_AGENT="nagent.py"
DEFAULT_USER="neptuneioagent"
NAGENT_CONFIG="nagent.cfg"
NAGENT_PLIST="com.neptune.agent.plist"
STABLE_NAGENT_URL="https://raw.githubusercontent.com/neptuneio/nagent/prod/src"

# Output display colors
red='\033[0;31m'
green='\033[0;32m'
NC='\033[0m' # No Color

# Set the endpoint
if [ -n "$NEPTUNE_ENDPOINT" ]; then
    END_POINT="$NEPTUNE_ENDPOINT"
    STABLE_NAGENT_URL="https://raw.githubusercontent.com/neptuneio/nagent/staging/src"
else
    END_POINT="www.neptune.io"
fi

# If the user name is not given, take the neptuneio user.
if [ -z "$NAGENT_USER" ]; then
    NAGENT_USER="$DEFAULT_USER"
fi
echo "Username: $NAGENT_USER"

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

# OS distribution should be Darwin, else prompt to user linux installer
OS_DISTRIBUTION=$(uname -s)
if [ "$OS_DISTRIBUTION" != "Darwin" ]; then
    echo -e "${red}Looks like this machine is not running on OSX. Please use linux installer instead ${NC}"
    exit 1
fi

# Check if python is installed
echo "-------------------------------------"
echo "Checking for python dependency"
if python -V ; then
    if `python -c "import sys; sys.exit(0 if sys.version_info < (2, 5) else 1)"`; then
        echo "Neptune agent needs Python >=2.6. Please upgrade Python and retry."y
        exit 1
    fi
    echo "Good to go..."
else
    echo -e "${red}Please install python 2.6 or higher and rerun. Exiting ${NC}"
    exit 1
fi

# Start install of agent
echo "Installing Neptuneio agent..."

# Install dependencies once based on linux distribution
if [ "$OS_DISTRIBUTION" == "Darwin" ]; then

    # Download pip directly and install
    $DOWNLOAD_CMD /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
    sudo -H python /tmp/get-pip.py
    sudo rm -rf /tmp/get-pip.py

    # Install pip packages
    if which pip &> /dev/null; then
        PIP_CMD=`which pip`
    elif ls /usr/local/bin/pip &> /dev/null; then
        PIP_CMD='/usr/local/bin/pip'
    else
        echo -e "${red}Pip installation unsuccessful. Please install pip manually and retry${NC}"
        exit 1
    fi
    # sudo -H $PIP_CMD install -U pyopenssl ndg-httpsclient pyasn1
    sudo -H $PIP_CMD install -U simplejson
    sudo -H $PIP_CMD install -U boto
    # If python version is less than 2.7, install requests version 2.5.0 to avoid
    # some unnecessary warnings on console.
    if `python -c "import sys; sys.exit(0 if sys.version_info < (2, 7) else 1)"`; then
        sudo -H $PIP_CMD install requests==2.5.0
    else
        sudo -H $PIP_CMD install -U requests
    fi
fi

# Create the new user if it does not exist
sudo id -u $NAGENT_USER &>/dev/null
if [ $? -ne 0 ]; then
    sudo dscl . -create /Users/$NAGENT_USER
    sudo dscl . -create /Users/$NAGENT_USER UserShell /bin/bash
    sudo dscl . -create /Users/$NAGENT_USER RealName "Neptune agent"
    LAST_ID=`sudo dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1`
    NEXT_ID=$((LAST_ID + 1))
    sudo dscl . -create /Users/$NAGENT_USER UniqueID $NEXT_ID
    sudo dscl . -create /Users/$NAGENT_USER PrimaryGroupID 20
    sudo dscl . -create /Users/$NAGENT_USER NFSHomeDirectory /Users/$NAGENT_USER
    sudo createhomedir -u $NAGENT_USER 2>&1 | grep -v "shell-init"
fi

# A Global variable but can be created only after creation of the user
NAGENT_HOME=`eval echo ~$NAGENT_USER/neptuneio`
echo "Home dir: $NAGENT_HOME"
sleep 2

# Create Neptune agent home directory
sudo mkdir -p $NAGENT_HOME

# Fetch the latest stable neptune agent and plist
echo "Fetching the latest stable version of neptuneio agent"
sudo $DOWNLOAD_CMD $NAGENT_HOME/$NEPTUNEIO_AGENT $STABLE_NAGENT_URL/$NEPTUNEIO_AGENT
sudo $DOWNLOAD_CMD $NAGENT_HOME/$NAGENT_PLIST $STABLE_NAGENT_URL/$NAGENT_PLIST

# Update user and agentn path in the plist
sudo sed -i.bak "s|AGENT_PATH|$NAGENT_HOME/$NEPTUNEIO_AGENT|" $NAGENT_HOME/$NAGENT_PLIST
sudo sed -i.bak "s|USER_NAME|$NAGENT_USER|" $NAGENT_HOME/$NAGENT_PLIST
sudo sed -i.bak "s|WORKING_DIRECTORY|$NAGENT_HOME|" $NAGENT_HOME/$NAGENT_PLIST
sudo rm -f $NAGENT_HOME/${NAGENT_PLIST}.bak

# Populate the neptuneio config
echo "Populating neptuneio agent config"
sudo bash -c "echo '[NEPTUNEIO]
API_KEY=$NEPTUNEIO_KEY
END_POINT=$END_POINT' > $NAGENT_HOME/$NAGENT_CONFIG"

# Add exec permissions to neptune agent, plist and config
sudo chmod 755 $NAGENT_HOME/$NEPTUNEIO_AGENT $NAGENT_HOME/$NAGENT_PLIST $NAGENT_HOME/$NAGENT_CONFIG

# Make the user as owner of the neptune agent home directory
sudo chown -R $NAGENT_USER $NAGENT_HOME

# Unload any existing neptune plist jobs
if [ -e  /Library/LaunchDaemons/$NAGENT_PLIST ]; then
    sudo launchctl unload -w /Library/LaunchDaemons/$NAGENT_PLIST
    sleep 3;
fi

# For OSX use launchctl to run it as a service
# Fetch agent plist
sudo cp $NAGENT_HOME/$NAGENT_PLIST /Library/LaunchDaemons

# Start the agent by loading the plist
echo "Starting Neptune agent..."
sudo launchctl load -w /Library/LaunchDaemons/$NAGENT_PLIST
# Check the status of daemon after 2 sec
sleep 2;
sudo launchctl list |grep neptune

echo "-------------------------------------"
echo "To check agent status run  : sudo launchctl list |grep neptune"
echo "To stop agent run          : sudo launchctl unload -w /Library/LaunchDaemons/$NAGENT_PLIST"
echo "To start agent run         : sudo launchctl load -w /Library/LaunchDaemons/$NAGENT_PLIST"
echo "Agent log available at     : $NAGENT_HOME/$NAGENT_LOG"

