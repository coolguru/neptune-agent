#!/bin/sh

########################
# Script to run a command on multiple hosts through SSH ; Can be used to install Neptuneio agent and run any other workload scripts remotely
# Usage : ./mass_deployment.sh
# Description : This script uses AWS CLI to get a list of ec2 hostnames and runs workload scripts on all the hosts
# Requirements : AWS CLI - Make sure your aws config has access to call aws ec2 describe-instances
# Contact : support@neptune.io
########################

########################
# Section 1 : Change these variables as appropriate
########################

# SSH keypair directory & name
KEYPAIR_DIRECTORY=`eval echo ~/.ssh/keypairs`
KEYPAIR="keypair_name.pem"

# AWS Region
AWS_REGION="us-east-1"

# AWS Tag (All servers under a tag will get agent installed)
TAG_KEY="Name"
TAG_VALUE="NodeAppCluster"

# Alternatively use Opsworks stackID instead of AWS tag above.(All servers under a stackID will get agent installed)
OPSWORKS_STACKID="OPSWORKS_STACK_ID_HERE"

# Username for SSH (Usually for Amazon linux its ec2-user, for RedHat & SUSE its root , for Ubuntu its ubuntu )
USERNAME="ec2-user"

########################
# Section 2 : Don't change these variables
########################

SSH_OPTIONS="-o StrictHostKeyChecking=no"

#########################

#################
# Section 3 : Copy the agent installation command with your Neptune.io API key into AGENT_INSTALL_CMD variable
#################

AGENT_INSTALL_CMD='AGENT_USER="neptune" API_KEY="API_KEY_HERE" bash -c "$(curl -sS -L https://raw.githubusercontent.com/neptuneio/neptune-agent/prod/scripts/linux/install_neptune_agent_linux.sh)"'
#################
# Agent control commands : Don't Change
#################

AGENT_START_CMD='sudo service neptune-agentd start'
AGENT_STOP_CMD='sudo service neptune-agentd stop'
AGENT_UPDATE_CMD='sudo service neptune-agentd update'
AGENT_RESTART_CMD='sudo service neptune-agentd restart'

#################

#################
# Get a host list and install Neptune.io agent
#################

# Use AWS CLI descrbe-instances to get host list based on AWS TAGS

for host in `aws ec2 describe-instances --region $AWS_REGION --filters "Name=tag-key,Values=$TAG_KEY,Name=tag-value,Values=$TAG_VALUE" | grep PublicIpAddress | cut -d "\"" -f4` ; do

# Alternatively use AWS CLI descrbe-instances to get host list based on Opsworks stackID
# for host in `aws opsworks --region $AWS_REGION describe-instances --stack-id $OPSWORKS_STACKID | grep PublicIp | cut -d "\"" -f4` ; do

echo "Installing Neptuneio agent on $host ....\n"

################
# Comment or uncomment agent actions as needed
################

# Install agent
ssh $SSH_OPTIONS -i $KEYPAIR_DIRECTORY/$KEYPAIR -t $USERNAME@$host $AGENT_INSTALL_CMD

# Update and restart agent
# ssh $SSH_OPTIONS -i $KEYPAIR_DIRECTORY/$KEYPAIR -t $USERNAME@$host $AGENT_UPDATE_CMD

done
