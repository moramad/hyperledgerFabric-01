#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This is a collection of bash functions used by different scripts

# imports
. scripts/utils.sh



export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export PEER1_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer1.org1.example.com/tls/ca.crt
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export PEER0_ORG3_CA=${PWD}/organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt

initVar() {
  export REMOTEIP="localhost"
  export REMOTEPATH="/MORAMAD/blockchain/FABRIC-STRUCTURE-ADD-ORG/network"

  export CA_IMAGETAG="1.5"
  export PEER_IMAGETAG="2.2.3"
  export COMPOSE_FILE_CA="docker/docker-compose-ca.yaml"
  export COMPOSE_FILE_CA2="docker/docker-compose-ca2.yaml"
  export COMPOSE_FILE_BASE="docker/docker-compose-test-net.yaml"
  export COMPOSE_FILE_BASE2="docker/docker-compose-test-net2.yaml"
  export COMPOSE_FILE_COUCH="docker/docker-compose-couch.yaml"
  export COMPOSE_FILE_COUCH2="docker/docker-compose-couch2.yaml"
  export GENESISBLOCKPROFILE="TwoOrgsOrdererGenesis"
  export GENESISBLOCKCHANNELID="system-channel"
  export GENESISBLOCKOUTPUT="./system-genesis-block/genesis.block"
  export DATABASE="couchdb"
  export CHANNEL_NAME="mychannel"
  export CHANNELTXPROFILE="TwoOrgsChannel"
  export OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
  export CRYPTO="Certificate Authorities"
  export BLOCKFILE="./channel-artifacts/${CHANNEL_NAME}.block"
  export MAX_RETRY="5"
  export CLI_DELAY="3"
  export DELAY="3"
  export CC_NAME="fabcar"
  export CC_SRC_PATH="../chaincode/fabcar/javascript"
  export CC_END_POLICY="NA"
  export CC_COLL_CONFIG="NA"
  export CC_INIT_FCN="initLedger"
  export CC_SRC_LANGUAGE="javascript"
  export CC_VERSION="1.0"
  export CC_SEQUENCE=1

  export ORG1="org1"
  export ORG1DOMAIN="org1.example.com"
  export ORG1CAHOST="localhost"
  export ORG1CAPORT="7054"
  export ORG1HOST="localhost"
  export ORG1IP="10.9.20.110"
  export ORG1IP="localhost"
  export ORG1PORT="7051"

  export ORG2="org2"
  export ORG2DOMAIN="org2.example.com"
  export ORG2CAHOST="10.9.20.140"
  export ORG2CAHOST="localhost"
  export ORG2CAPORT="8054"
  export ORG2HOST="10.9.20.140"
  export ORG2HOST="localhost"
  export ORG2IP="10.9.20.140"
  export ORG2IP="localhost"
  export ORG2PORT="9051"

  export ORDERERDOMAIN="example.com"
  export ORDERERNAMEDOMAIN="orderer.example.com"
  export ORDERERCAHOST="localhost"
  export ORDERERCAPORT="9054"
  export ORDERERHOST="localhost"
  export ORDERERIP="10.9.20.110"
  export ORDERERPORT="7050"  
}

setVar() {
  local USING_ORG=""
  USING_ORG=$1
  if [ $USING_ORG -eq 1 ]; then
    export ORG="org1"
    export ORGDOMAIN="org1.example.com"
    export ORGCAHOST="localhost"
    export ORGCAPORT="7054"
    export ORGHOST="localhost"    
    export ORGIP="localhost"
    export ORGPORT="7051"
  elif [ $USING_ORG -eq 2 ]; then
    export ORG="org2"
    export ORGDOMAIN="org2.example.com"
    export ORGCAHOST="localhost"
    export ORGCAPORT="8054"
    export ORGHOST="localhost"    
    export ORGIP="localhost"
    export ORGPORT="9051"
  fi
}

# Set environment variables for the peer org
setGlobals() {
  local USING_ORG=""
  if [ -z "$OVERRIDE_ORG" ]; then
    USING_ORG=$1
  else
    USING_ORG="${OVERRIDE_ORG}"
  fi
  infoln "Using organization ${USING_ORG}"
  if [ $USING_ORG -eq 1 ]; then
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG1_CA
    export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
    export CORE_PEER_ADDRESS=localhost:7051
  elif [ $USING_ORG -eq 2 ]; then
    export CORE_PEER_LOCALMSPID="Org2MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG2_CA
    export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    export CORE_PEER_ADDRESS=peer0.org2.example.com:9051

  elif [ $USING_ORG -eq 3 ]; then
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$PEER1_ORG1_CA
    export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
    export CORE_PEER_ADDRESS=localhost:8051
  else
    errorln "ORG Unknown"
  fi

  if [ "$VERBOSE" == "true" ]; then
    env | grep CORE
  fi
}

# Set environment variables for use in the CLI container 
setGlobalsCLI() {
  setGlobals $1

  local USING_ORG=""
  if [ -z "$OVERRIDE_ORG" ]; then
    USING_ORG=$1
  else
    USING_ORG="${OVERRIDE_ORG}"
  fi
  if [ $USING_ORG -eq 1 ]; then
    export CORE_PEER_ADDRESS=peer0.org1.example.com:7051
  elif [ $USING_ORG -eq 2 ]; then
    export CORE_PEER_ADDRESS=peer0.org2.example.com:9051
  elif [ $USING_ORG -eq 3 ]; then
    export CORE_PEER_ADDRESS=peer1.org1.example.com:8051
  else
    errorln "ORG Unknown"
  fi
}

# parsePeerConnectionParameters $@
# Helper function that sets the peer connection parameters for a chaincode
# operation
parsePeerConnectionParameters() {
  PEER_CONN_PARMS=""
  PEERS=""
  while [ "$#" -gt 0 ]; do
    setGlobals $1
    PEER="peer0.org$1"
    ## Set peer addresses
    PEERS="$PEERS $PEER"
    PEER_CONN_PARMS="$PEER_CONN_PARMS --peerAddresses $CORE_PEER_ADDRESS"
    ## Set path to TLS certificate
    TLSINFO=$(eval echo "--tlsRootCertFiles \$PEER0_ORG$1_CA")
    PEER_CONN_PARMS="$PEER_CONN_PARMS $TLSINFO"
    # shift by one to get to the next organization
    shift
  done
  # remove leading space for output
  PEERS="$(echo -e "$PEERS" | sed -e 's/^[[:space:]]*//')"
}

verifyResult() {
  res=$1  
  if [ ${res} -ne 0 ]; then
    fatalln "$2"
  fi
}
