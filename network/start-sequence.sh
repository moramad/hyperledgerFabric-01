#!/bin/bash

export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export VERBOSE=false

##################################
. scripts/utils.sh
. scripts/envVar.sh
. scripts/functionCatalog.sh
  initVar
##################################

# # unset http_proxy
# # unset https_proxy
  
# network_down
# # setup_swarm

# createCryptoMaterial

# createIdentityOrg 1
# createIdentityOrg 2
# createIdentityOrderer

# ccp-generator 1
# ccp-generator 2

# generateGenesisBlock

# infoln "sync organizations dir to remote server : ${REMOTEIP}"
# scp -pr -q -o LogLevel=QUIET organizations/* ${REMOTEIP}:${REMOTEPATH}/organizations
# scp -pr -q -o LogLevel=QUIET system-genesis-block/* ${REMOTEIP}:${REMOTEPATH}/system-genesis-block

# createPeer

# initiateChannel

deployChaincode $CHANNEL_NAME $CC_NAME $CC_SRC_PATH $CC_SRC_LANGUAGE $CC_VERSION $CC_SEQUENCE $CC_INIT_FCN $CC_END_POLICY $CC_COLL_CONFIG $CLI_DELAY $MAX_RETRY $VERBOSE