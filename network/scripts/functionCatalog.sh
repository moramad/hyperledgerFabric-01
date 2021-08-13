#!/bin/bash

#########################################
export PATH=${PWD}/../bin:$PATH
. scripts/utils.sh
. scripts/envVar.sh

function remote() {    
    ssh root@$REMOTEIP "cd ${REMOTEPATH} && $1"
}

function network_down() {
    infoln "shutdown system before"
    docker-compose -f $COMPOSE_FILE_BASE -f $COMPOSE_FILE_COUCH -f $COMPOSE_FILE_CA down --volumes --remove-orphans
    docker volume prune -f
    # Don't remove the generated artifacts -- note, the ledgers are always removed
    if [ "$MODE" != "restart" ]; then
        # Bring down the network, deleting the volumes
        # remove orderer block and other channel configuration transactions and certs
        docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf system-genesis-block/*.block organizations/peerOrganizations organizations/ordererOrganizations'
        # remove fabric ca artifacts
        docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db'
        docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db'
        docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db'
        docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf addOrg3/fabric-ca/org3/msp addOrg3/fabric-ca/org3/tls-cert.pem addOrg3/fabric-ca/org3/ca-cert.pem addOrg3/fabric-ca/org3/IssuerPublicKey addOrg3/fabric-ca/org3/IssuerRevocationPublicKey addOrg3/fabric-ca/org3/fabric-ca-server.db'
        # remove channel and script artifacts
        docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'
    fi    
    infoln "shutdown system before in remote server : ${REMOTEIP}"
    remote "docker-compose -f ${COMPOSE_FILE_BASE2} -f ${COMPOSE_FILE_COUCH2} -f ${COMPOSE_FILE_CA2} down --volumes --remove-orphans"    
    remote "docker volume prune -f"
    remote "rm -rf system-genesis-block/*.block organizations/peerOrganizations organizations/ordererOrganizations"
    remote "rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db"
    remote "rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db"
    remote "rm -rf organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db"
    remote "rm -rf channel-artifacts log.txt *.tar.gz"

}

function setup_swarm() {
    docker swarm leave --force
    remote "docker swarm leave --force"

    docker swarm init --advertise-addr ${ORG1IP}
    RESULT=$(docker swarm join-token manager | grep docker | cut -d' ' -f9)
    remote "docker swarm join --token ${RESULT} ${ORG1IP}:2377 --advertise-addr ${ORG2IP}"
    docker network create --attachable --driver overlay dev_test
}


#########################################
function createCryptoMaterial() {    
    infoln "Generating certificates using Fabric CA"

    IMAGE_TAG=${CA_IMAGETAG} docker-compose -f $COMPOSE_FILE_CA up -d 2>&1    
    
    sleep 3
    if [ ! -f "organizations/fabric-ca/${ORG1}/tls-cert.pem" ]; then
        fatalln "tls-cert.pem not found"    
    fi
    
    infoln "Generating certificates using Fabric CA in remote server : ${REMOTEIP}"
    remote "IMAGE_TAG=${CA_IMAGETAG} docker-compose -f ${REMOTEPATH}/${COMPOSE_FILE_CA2} up -d 2>&1"
    scp -pr -q -o logLevel=QUIET organizations/fabric-ca/${ORG2} ${REMOTEIP}:${REMOTEPATH}/organizations/fabric-ca/
}
##################################
function createIdentityOrg() {
    setVar $1
    infoln "Enrolling the CA admin"
    mkdir -p organizations/peerOrganizations/${ORGDOMAIN}/

    export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/

    set -x
    fabric-ca-client enroll -u https://admin:adminpw@${ORGCAHOST}:${ORGCAPORT} --caname ca-${ORG} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    echo "NodeOUs:
    Enable: true
    ClientOUIdentifier:
      Certificate: cacerts/${ORGCAHOST}-${ORGCAPORT}-ca-${ORG}.pem
      OrganizationalUnitIdentifier: client
    PeerOUIdentifier:
      Certificate: cacerts/${ORGCAHOST}-${ORGCAPORT}-ca-${ORG}.pem
      OrganizationalUnitIdentifier: peer
    AdminOUIdentifier:
      Certificate: cacerts/${ORGCAHOST}-${ORGCAPORT}-ca-${ORG}.pem
      OrganizationalUnitIdentifier: admin
    OrdererOUIdentifier:
      Certificate: cacerts/${ORGCAHOST}-${ORGCAPORT}-ca-${ORG}.pem
      OrganizationalUnitIdentifier: orderer" >${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/msp/config.yaml

    infoln "Registering peer0"
    set -x
    fabric-ca-client register --caname ca-${ORG} --id.name peer0 --id.secret peer0pw --id.type peer --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    infoln "Registering user"
    set -x
    fabric-ca-client register --caname ca-${ORG} --id.name user1 --id.secret user1pw --id.type client --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    infoln "Registering the org admin"
    set -x
    fabric-ca-client register --caname ca-${ORG} --id.name ${ORG}admin --id.secret ${ORG}adminpw --id.type admin --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    infoln "Generating the peer0 msp"
    set -x
    fabric-ca-client enroll -u https://peer0:peer0pw@${ORGCAHOST}:${ORGCAPORT} --caname ca-${ORG} -M ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/msp --csr.hosts peer0.${ORGDOMAIN} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/msp/config.yaml

    infoln "Generating the peer0-tls certificates"
    set -x
    fabric-ca-client enroll -u https://peer0:peer0pw@${ORGCAHOST}:${ORGCAPORT} --caname ca-${ORG} -M ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls --enrollment.profile tls --csr.hosts peer0.${ORGDOMAIN} --csr.hosts ${ORGCAHOST} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/ca.crt
    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/signcerts/* ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/server.crt
    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/keystore/* ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/server.key

    mkdir -p ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/msp/tlscacerts
    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/msp/tlscacerts/ca.crt

    mkdir -p ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/tlsca
    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/tlsca/tlsca.${ORGDOMAIN}-cert.pem

    mkdir -p ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/ca
    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/peers/peer0.${ORGDOMAIN}/msp/cacerts/* ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/ca/ca.${ORGDOMAIN}-cert.pem

    infoln "Generating the user msp"
    set -x
    fabric-ca-client enroll -u https://user1:user1pw@${ORGCAHOST}:${ORGCAPORT} --caname ca-${ORG} -M ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/users/User1@${ORGDOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/users/User1@${ORGDOMAIN}/msp/config.yaml

    infoln "Generating the org admin msp"
    set -x
    fabric-ca-client enroll -u https://${ORG}admin:${ORG}adminpw@${ORGCAHOST}:${ORGCAPORT} --caname ca-${ORG} -M ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/users/Admin@${ORGDOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG}/tls-cert.pem
    { set +x; } 2>/dev/null

    cp ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORGDOMAIN}/users/Admin@${ORGDOMAIN}/msp/config.yaml
}

function createIdentityOrg1() {
  infoln "Enrolling the CA admin"
  mkdir -p organizations/peerOrganizations/${ORG1DOMAIN}/

  export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/

  set -x
  fabric-ca-client enroll -u https://admin:adminpw@${ORG1CAHOST}:${ORG1CAPORT} --caname ca-${ORG1} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  echo "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${ORG1CAHOST}-${ORG1CAPORT}-ca-${ORG1}.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${ORG1CAHOST}-${ORG1CAPORT}-ca-${ORG1}.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${ORG1CAHOST}-${ORG1CAPORT}-ca-${ORG1}.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${ORG1CAHOST}-${ORG1CAPORT}-ca-${ORG1}.pem
    OrganizationalUnitIdentifier: orderer" >${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/msp/config.yaml

  infoln "Registering peer0"
  set -x
  fabric-ca-client register --caname ca-${ORG1} --id.name peer0 --id.secret peer0pw --id.type peer --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Registering user"
  set -x
  fabric-ca-client register --caname ca-${ORG1} --id.name user1 --id.secret user1pw --id.type client --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Registering the org admin"
  set -x
  fabric-ca-client register --caname ca-${ORG1} --id.name ${ORG1}admin --id.secret ${ORG1}adminpw --id.type admin --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Generating the peer0 msp"
  set -x
  fabric-ca-client enroll -u https://peer0:peer0pw@${ORG1CAHOST}:${ORG1CAPORT} --caname ca-${ORG1} -M ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/msp --csr.hosts peer0.${ORG1DOMAIN} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/msp/config.yaml

  infoln "Generating the peer0-tls certificates"
  set -x
  fabric-ca-client enroll -u https://peer0:peer0pw@${ORG1CAHOST}:${ORG1CAPORT} --caname ca-${ORG1} -M ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls --enrollment.profile tls --csr.hosts peer0.${ORG1DOMAIN} --csr.hosts ${ORG1CAHOST} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/ca.crt
  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/signcerts/* ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/server.crt
  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/keystore/* ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/server.key

  mkdir -p ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/msp/tlscacerts
  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/msp/tlscacerts/ca.crt

  mkdir -p ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/tlsca
  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/tlsca/tlsca.${ORG1DOMAIN}-cert.pem

  mkdir -p ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/ca
  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/peers/peer0.${ORG1DOMAIN}/msp/cacerts/* ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/ca/ca.${ORG1DOMAIN}-cert.pem

  infoln "Generating the user msp"
  set -x
  fabric-ca-client enroll -u https://user1:user1pw@${ORG1CAHOST}:${ORG1CAPORT} --caname ca-${ORG1} -M ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/users/User1@${ORG1DOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/users/User1@${ORG1DOMAIN}/msp/config.yaml

  infoln "Generating the org admin msp"
  set -x
  fabric-ca-client enroll -u https://${ORG1}admin:${ORG1}adminpw@${ORG1CAHOST}:${ORG1CAPORT} --caname ca-${ORG1} -M ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/users/Admin@${ORG1DOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG1}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORG1DOMAIN}/users/Admin@${ORG1DOMAIN}/msp/config.yaml
}

function createIdentityOrg2() {
  infoln "Enrolling the CA admin"
  mkdir -p organizations/peerOrganizations/${ORG2DOMAIN}/

  export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/

  set -x
  fabric-ca-client enroll -u https://admin:adminpw@${ORG2CAHOST}:${ORG2CAPORT} --caname ca-${ORG2} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  echo "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${ORG2CAHOST}-${ORG2CAPORT}-ca-${ORG2}.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${ORG2CAHOST}-${ORG2CAPORT}-ca-${ORG2}.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${ORG2CAHOST}-${ORG2CAPORT}-ca-${ORG2}.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${ORG2CAHOST}-${ORG2CAPORT}-ca-${ORG2}.pem
    OrganizationalUnitIdentifier: orderer" >${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/msp/config.yaml

  infoln "Registering peer0"
  set -x
  fabric-ca-client register --caname ca-${ORG2} --id.name peer0 --id.secret peer0pw --id.type peer --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Registering user"
  set -x
  fabric-ca-client register --caname ca-${ORG2} --id.name user1 --id.secret user1pw --id.type client --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Registering the org admin"
  set -x
  fabric-ca-client register --caname ca-${ORG2} --id.name ${ORG2}admin --id.secret ${ORG2}adminpw --id.type admin --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Generating the peer0 msp"
  set -x
  fabric-ca-client enroll -u https://peer0:peer0pw@${ORG2CAHOST}:${ORG2CAPORT} --caname ca-${ORG2} -M ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/msp --csr.hosts peer0.${ORG2DOMAIN} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/msp/config.yaml

  infoln "Generating the peer0-tls certificates"
  set -x
  fabric-ca-client enroll -u https://peer0:peer0pw@${ORG2CAHOST}:${ORG2CAPORT} --caname ca-${ORG2} -M ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls --enrollment.profile tls --csr.hosts peer0.${ORG2DOMAIN} --csr.hosts ${ORG2CAHOST} --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/ca.crt
  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/signcerts/* ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/server.crt
  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/keystore/* ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/server.key

  mkdir -p ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/msp/tlscacerts
  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/msp/tlscacerts/ca.crt

  mkdir -p ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/tlsca
  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/tls/tlscacerts/* ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/tlsca/tlsca.${ORG2DOMAIN}-cert.pem

  mkdir -p ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/ca
  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/peers/peer0.${ORG2DOMAIN}/msp/cacerts/* ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/ca/ca.${ORG2DOMAIN}-cert.pem

  infoln "Generating the user msp"
  set -x
  fabric-ca-client enroll -u https://user1:user1pw@${ORG2CAHOST}:${ORG2CAPORT} --caname ca-${ORG2} -M ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/users/User1@${ORG2DOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/users/User1@${ORG2DOMAIN}/msp/config.yaml

  infoln "Generating the org admin msp"
  set -x
  fabric-ca-client enroll -u https://${ORG2}admin:${ORG2}adminpw@${ORG2CAHOST}:${ORG2CAPORT} --caname ca-${ORG2} -M ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/users/Admin@${ORG2DOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/${ORG2}/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/msp/config.yaml ${PWD}/organizations/peerOrganizations/${ORG2DOMAIN}/users/Admin@${ORG2DOMAIN}/msp/config.yaml
}

function createIdentityOrderer() {
  infoln "Enrolling the CA admin"
  mkdir -p organizations/ordererOrganizations/${ORDERERDOMAIN}

  export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}

  set -x
  fabric-ca-client enroll -u https://admin:adminpw@${ORDERERCAHOST}:${ORDERERCAPORT} --caname ca-orderer --tls.certfiles ${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem
  { set +x; } 2>/dev/null

  echo "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/${ORDERERCAHOST}-${ORDERERCAPORT}-ca-orderer.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/${ORDERERCAHOST}-${ORDERERCAPORT}-ca-orderer.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/${ORDERERCAHOST}-${ORDERERCAPORT}-ca-orderer.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/${ORDERERCAHOST}-${ORDERERCAPORT}-ca-orderer.pem
    OrganizationalUnitIdentifier: orderer" >${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/msp/config.yaml

  infoln "Registering orderer"
  set -x
  fabric-ca-client register --caname ca-orderer --id.name orderer --id.secret ordererpw --id.type orderer --tls.certfiles ${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Registering the orderer admin"
  set -x
  fabric-ca-client register --caname ca-orderer --id.name ordererAdmin --id.secret ordererAdminpw --id.type admin --tls.certfiles ${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem
  { set +x; } 2>/dev/null

  infoln "Generating the orderer msp"
  set -x
  fabric-ca-client enroll -u https://orderer:ordererpw@${ORDERERCAHOST}:${ORDERERCAPORT} --caname ca-orderer -M ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/msp --csr.hosts ${ORDERERNAMEDOMAIN} --csr.hosts ${ORDERERCAHOST} --tls.certfiles ${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/msp/config.yaml ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/msp/config.yaml

  infoln "Generating the orderer-tls certificates"
  set -x
  fabric-ca-client enroll -u https://orderer:ordererpw@${ORDERERCAHOST}:${ORDERERCAPORT} --caname ca-orderer -M ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls --enrollment.profile tls --csr.hosts ${ORDERERNAMEDOMAIN} --csr.hosts ${ORDERERCAHOST} --tls.certfiles ${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/tlscacerts/* ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/ca.crt
  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/signcerts/* ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/server.crt
  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/keystore/* ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/server.key

  mkdir -p ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/msp/tlscacerts
  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/tlscacerts/* ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/msp/tlscacerts/tlsca.${ORDERERDOMAIN}-cert.pem

  mkdir -p ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/msp/tlscacerts
  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/orderers/${ORDERERNAMEDOMAIN}/tls/tlscacerts/* ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/msp/tlscacerts/tlsca.${ORDERERDOMAIN}-cert.pem

  infoln "Generating the admin msp"
  set -x
  fabric-ca-client enroll -u https://ordererAdmin:ordererAdminpw@${ORDERERCAHOST}:${ORDERERCAPORT} --caname ca-orderer -M ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/users/Admin@${ORDERERDOMAIN}/msp --tls.certfiles ${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem
  { set +x; } 2>/dev/null

  cp ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/msp/config.yaml ${PWD}/organizations/ordererOrganizations/${ORDERERDOMAIN}/users/Admin@${ORDERERDOMAIN}/msp/config.yaml  
}
##################################
function one_line_pem {
    echo "`awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' $1`"
}

function json_ccp {
    local PP=$(one_line_pem $4)
    local CP=$(one_line_pem $5)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${P0PORT}/$2/" \
        -e "s/\${CAPORT}/$3/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        organizations/ccp-template.json
}

function yaml_ccp {
    local PP=$(one_line_pem $4)
    local CP=$(one_line_pem $5)
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${P0PORT}/$2/" \
        -e "s/\${CAPORT}/$3/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        organizations/ccp-template.yaml | sed -e $'s/\\\\n/\\\n          /g'
}

function ccp-generator() {
    setVar $1
    
    PEERPEM=organizations/peerOrganizations/${ORGDOMAIN}/tlsca/tlsca.${ORGDOMAIN}-cert.pem
    CAPEM=organizations/peerOrganizations/${ORGDOMAIN}/ca/ca.${ORGDOMAIN}-cert.pem

    echo "$(json_ccp $ORG $ORGPORT $ORGCAPORT $PEERPEM $CAPEM)" > organizations/peerOrganizations/${ORGDOMAIN}/connection-${ORG}.json
    echo "$(yaml_ccp $ORG $ORGPORT $ORGCAPORT $PEERPEM $CAPEM)" > organizations/peerOrganizations/${ORGDOMAIN}/connection-${ORG}.yaml  
    

}
##################################
function generateGenesisBlock() {
  infoln "Generating Orderer Genesis block"

  set -x
  configtxgen -profile $GENESISBLOCKPROFILE -channelID $GENESISBLOCKCHANNELID -outputBlock $GENESISBLOCKOUTPUT
  res=$?
  { set +x; } 2>/dev/null
  if [ $res -ne 0 ]; then
    fatalln "Failed to generate orderer genesis block..."
  fi
}
##################################
function createPeer() {       
    infoln "Composing docker container for Peer" 
    IMAGE_TAG=$PEER_IMAGETAG docker-compose -f ${COMPOSE_FILE_BASE} -f ${COMPOSE_FILE_COUCH} up -d 2>&1

    RESULT=$(docker ps -a)
    if [ $? -ne 0 ]; then
        fatalln "Unable to start network"
    fi
    
    infoln "Composing docker container for Peer in remote server : ${REMOTEIP}" 
    remote "IMAGE_TAG=$PEER_IMAGETAG docker-compose -f ${COMPOSE_FILE_BASE2} -f ${COMPOSE_FILE_COUCH2} up -d 2>&1"                
}
##################################
createChannelTx() {
	set -x
	configtxgen -profile $CHANNELTXPROFILE -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
	res=$?
	{ set +x; } 2>/dev/null
  verifyResult $res "Failed to generate channel configuration transaction..."
}

createChannel() {
	setGlobals 1
	# Poll in case the raft leader is not set yet
	local rc=1
	local COUNTER=1
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
		sleep $DELAY
		set -x
		peer channel create -o ${ORDERERHOST}:${ORDERERPORT} -c $CHANNEL_NAME --ordererTLSHostnameOverride ${ORDERERNAMEDOMAIN} -f ./channel-artifacts/${CHANNEL_NAME}.tx --outputBlock $BLOCKFILE --tls --cafile $ORDERER_CA >&log.txt
		res=$?
		{ set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "Channel creation failed"
}

joinChannel() {
  FABRIC_CFG_PATH=$PWD/../config/
  ORG=$1
  setGlobals $ORG
  
	local rc=1
	local COUNTER=1
	## Sometimes Join takes time, hence retry  
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE >&log.txt
    res=$?
    { set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "After $MAX_RETRY attempts, peer0.org${ORG} has failed to join channel '$CHANNEL_NAME' "
}

setAnchorPeer() {
  ORG=$1
  docker exec cli ./scripts/setAnchorPeer.sh $ORG $CHANNEL_NAME 
}

function initiateChannel() {
  FABRIC_CFG_PATH=${PWD}/configtx

  ## Create channeltx
  infoln "Generating channel create transaction '${CHANNEL_NAME}.tx'"
  createChannelTx

  FABRIC_CFG_PATH=$PWD/../config/  

  ## Create channel
  infoln "Creating channel ${CHANNEL_NAME}"
  createChannel
  successln "Channel '$CHANNEL_NAME' created"

  ## Join all the peers to the channel
  infoln "Joining ${ORG1} peer to the channel..."
  joinChannel 1

  ssh ${REMOTEIP} "mkdir ${REMOTEPATH}/channel-artifacts"
  scp -pr -q -o logLevel=QUIET channel-artifacts/* ${REMOTEIP}:${REMOTEPATH}/channel-artifacts

  infoln "Joining ${ORG2} peer to the channel..."
  remote "export FABRIC_CFG_PATH=$PWD/../config/ && . scripts/functionCatalog.sh && initVar && joinChannel 2"

  # Set the anchor peers for each org in the channel
  infoln "Setting anchor peer for ${ORG1}..."
  setAnchorPeer 1

  infoln "Setting anchor peer for ${ORG2}..."
  remote "export FABRIC_CFG_PATH=$PWD/../config/ && . scripts/functionCatalog.sh && initVar && setAnchorPeer 2"

  successln "Channel '$CHANNEL_NAME' joined"
}
##################################
packageChaincode() {
  set -x
  peer lifecycle chaincode package ${CC_NAME}.tar.gz --path ${CC_SRC_PATH} --lang ${CC_RUNTIME_LANGUAGE} --label ${CC_NAME}_${CC_VERSION} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode packaging has failed"
  successln "Chaincode is packaged"
}

# installChaincode PEER ORG
installChaincode() {
  ORG=$1
  setGlobals $ORG
  set -x
  peer lifecycle chaincode install ${CC_NAME}.tar.gz >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode installation on peer0.org${ORG} has failed"
  successln "Chaincode is installed on peer0.org${ORG}"
}

# queryInstalled PEER ORG
queryInstalled() {
  ORG=$1
  setGlobals $ORG
  set -x
  peer lifecycle chaincode queryinstalled >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  PACKAGE_ID=$(sed -n "/${CC_NAME}_${CC_VERSION}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
  verifyResult $res "Query installed on peer0.org${ORG} has failed"
  successln "Query installed successful on peer0.org${ORG} on channel"
}

# approveForMyOrg VERSION PEER ORG
approveForMyOrg() {
  ORG=$1
  setGlobals $ORG
  set -x
  peer lifecycle chaincode approveformyorg -o ${ORDERERHOST}:${ORDERERPORT} --ordererTLSHostnameOverride ${ORDERERNAMEDOMAIN} --tls --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --package-id ${PACKAGE_ID} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode definition approved on peer0.org${ORG} on channel '$CHANNEL_NAME' failed"
  successln "Chaincode definition approved on peer0.org${ORG} on channel '$CHANNEL_NAME'"
}

# checkCommitReadiness VERSION PEER ORG
checkCommitReadiness() {
  ORG=$1
  shift 1
  setGlobals $ORG
  infoln "Checking the commit readiness of the chaincode definition on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
  local rc=1
  local COUNTER=1
  # continue to poll
  # we either get a successful response, or reach MAX RETRY
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $DELAY
    infoln "Attempting to check the commit readiness of the chaincode definition on peer0.org${ORG}, Retry after $DELAY seconds."
    set -x
    peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} --output json >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=0
    for var in "$@"; do
      grep "$var" log.txt &>/dev/null || let rc=1
    done
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  if test $rc -eq 0; then
    infoln "Checking the commit readiness of the chaincode definition successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
  else
    fatalln "After $MAX_RETRY attempts, Check commit readiness result on peer0.org${ORG} is INVALID!"
  fi
}

# commitChaincodeDefinition VERSION PEER ORG (PEER ORG)...
commitChaincodeDefinition() {
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  
  set -x
  peer lifecycle chaincode commit -o ${ORDERERHOST}:${ORDERERPORT} --ordererTLSHostnameOverride ${ORDERERNAMEDOMAIN} --tls --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name ${CC_NAME} $PEER_CONN_PARMS --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode definition commit failed on peer0.org${ORG} on channel '$CHANNEL_NAME' failed"
  successln "Chaincode definition committed on channel '$CHANNEL_NAME'"
}

# queryCommitted ORG
queryCommitted() {
  ORG=$1
  setGlobals $ORG
  EXPECTED_RESULT="Version: ${CC_VERSION}, Sequence: ${CC_SEQUENCE}, Endorsement Plugin: escc, Validation Plugin: vscc"
  infoln "Querying chaincode definition on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
  local rc=1
  local COUNTER=1
  # continue to poll
  # we either get a successful response, or reach MAX RETRY
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $DELAY
    infoln "Attempting to Query committed status on peer0.org${ORG}, Retry after $DELAY seconds."
    set -x
    peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name ${CC_NAME} >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    test $res -eq 0 && VALUE=$(cat log.txt | grep -o '^Version: '$CC_VERSION', Sequence: [0-9]*, Endorsement Plugin: escc, Validation Plugin: vscc')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  if test $rc -eq 0; then
    successln "Query chaincode definition successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
  else
    fatalln "After $MAX_RETRY attempts, Query chaincode definition result on peer0.org${ORG} is INVALID!"
  fi
}

chaincodeInvokeInit() {
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  set -x
  fcn_call='{"function":"'${CC_INIT_FCN}'","Args":[]}'
  infoln "invoke fcn call:${fcn_call}"
  peer chaincode invoke -o ${ORDERERHOST}:${ORDERERPORT} --ordererTLSHostnameOverride ${ORDERERNAMEDOMAIN} --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n ${CC_NAME} $PEER_CONN_PARMS --isInit -c ${fcn_call} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Invoke execution on $PEERS failed "
  successln "Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME'"
}

chaincodeQuery() {
  ORG=$1
  setGlobals $ORG
  infoln "Querying on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
  local rc=1
  local COUNTER=1
  # continue to poll
  # we either get a successful response, or reach MAX RETRY
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $DELAY
    infoln "Attempting to Query peer0.org${ORG}, Retry after $DELAY seconds."
    set -x
    peer chaincode query -C $CHANNEL_NAME -n ${CC_NAME} -c '{"Args":["queryAllCars"]}' >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=$res
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  if test $rc -eq 0; then
    successln "Query successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
  else
    fatalln "After $MAX_RETRY attempts, Query result on peer0.org${ORG} is INVALID!"
  fi
}

function deployChaincode() {
  source scripts/utils.sh

  CHANNEL_NAME=${1:-"mychannel"}
  CC_NAME=${2}
  CC_SRC_PATH=${3}
  CC_SRC_LANGUAGE=${4}
  CC_VERSION=${5:-"1.0"}
  CC_SEQUENCE=${6:-"1"}
  CC_INIT_FCN=${7:-"NA"}
  CC_END_POLICY=${8:-"NA"}
  CC_COLL_CONFIG=${9:-"NA"}
  DELAY=${10:-"3"}
  MAX_RETRY=${11:-"5"}
  VERBOSE=${12:-"false"}

  println "executing with the following"
  println "- CHANNEL_NAME: ${C_GREEN}${CHANNEL_NAME}${C_RESET}"
  println "- CC_NAME: ${C_GREEN}${CC_NAME}${C_RESET}"
  println "- CC_SRC_PATH: ${C_GREEN}${CC_SRC_PATH}${C_RESET}"
  println "- CC_SRC_LANGUAGE: ${C_GREEN}${CC_SRC_LANGUAGE}${C_RESET}"
  println "- CC_VERSION: ${C_GREEN}${CC_VERSION}${C_RESET}"
  println "- CC_SEQUENCE: ${C_GREEN}${CC_SEQUENCE}${C_RESET}"
  println "- CC_END_POLICY: ${C_GREEN}${CC_END_POLICY}${C_RESET}"
  println "- CC_COLL_CONFIG: ${C_GREEN}${CC_COLL_CONFIG}${C_RESET}"
  println "- CC_INIT_FCN: ${C_GREEN}${CC_INIT_FCN}${C_RESET}"
  println "- DELAY: ${C_GREEN}${DELAY}${C_RESET}"
  println "- MAX_RETRY: ${C_GREEN}${MAX_RETRY}${C_RESET}"
  println "- VERBOSE: ${C_GREEN}${VERBOSE}${C_RESET}"

  FABRIC_CFG_PATH=$PWD/../config/

  #User has not provided a name
  if [ -z "$CC_NAME" ] || [ "$CC_NAME" = "NA" ]; then
    fatalln "No chaincode name was provided. Valid call example: ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"

  # User has not provided a path
  elif [ -z "$CC_SRC_PATH" ] || [ "$CC_SRC_PATH" = "NA" ]; then
    fatalln "No chaincode path was provided. Valid call example: ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"

  # User has not provided a language
  elif [ -z "$CC_SRC_LANGUAGE" ] || [ "$CC_SRC_LANGUAGE" = "NA" ]; then
    fatalln "No chaincode language was provided. Valid call example: ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"

  ## Make sure that the path to the chaincode exists
  elif [ ! -d "$CC_SRC_PATH" ]; then
    fatalln "Path to chaincode does not exist. Please provide different path."
  fi

  CC_SRC_LANGUAGE=$(echo "$CC_SRC_LANGUAGE" | tr [:upper:] [:lower:])

  # do some language specific preparation to the chaincode before packaging
  if [ "$CC_SRC_LANGUAGE" = "go" ]; then
    CC_RUNTIME_LANGUAGE=golang

    infoln "Vendoring Go dependencies at $CC_SRC_PATH"
    pushd $CC_SRC_PATH
    GO111MODULE=on go mod vendor
    popd
    successln "Finished vendoring Go dependencies"

  elif [ "$CC_SRC_LANGUAGE" = "java" ]; then
    CC_RUNTIME_LANGUAGE=java

    infoln "Compiling Java code..."
    pushd $CC_SRC_PATH
    ./gradlew installDist
    popd
    successln "Finished compiling Java code"
    CC_SRC_PATH=$CC_SRC_PATH/build/install/$CC_NAME

  elif [ "$CC_SRC_LANGUAGE" = "javascript" ]; then
    CC_RUNTIME_LANGUAGE=node

  elif [ "$CC_SRC_LANGUAGE" = "typescript" ]; then
    CC_RUNTIME_LANGUAGE=node

    infoln "Compiling TypeScript code into JavaScript..."
    pushd $CC_SRC_PATH
    npm install
    npm run build
    popd
    successln "Finished compiling TypeScript code into JavaScript"

  else
    fatalln "The chaincode language ${CC_SRC_LANGUAGE} is not supported by this script. Supported chaincode languages are: go, java, javascript, and typescript"
    exit 1
  fi

  INIT_REQUIRED="--init-required"
  # check if the init fcn should be called
  if [ "$CC_INIT_FCN" = "NA" ]; then
    INIT_REQUIRED=""
  fi

  if [ "$CC_END_POLICY" = "NA" ]; then
    CC_END_POLICY=""
  else
    CC_END_POLICY="--signature-policy $CC_END_POLICY"
  fi

  if [ "$CC_COLL_CONFIG" = "NA" ]; then
    CC_COLL_CONFIG=""
  else
    CC_COLL_CONFIG="--collections-config $CC_COLL_CONFIG"
  fi

  # import utils
  . scripts/envVar.sh

  # package the chaincode
  packageChaincode

  # Install chaincode on peer0.${ORG1}
  infoln "Installing chaincode on peer0.${ORG1}..."
  installChaincode 1

  # query whether the chaincode is installed
  queryInstalled 1

  # approve the definition for ${ORG1}
  approveForMyOrg 1

  # check whether the chaincode definition is ready to be committed
  # expect ${ORG1} to have approved and ${ORG2} not to
  checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": false"

  # remote deployChaincode

  ## now that we know for sure both orgs have approved, commit the definition
  commitChaincodeDefinition 1 2

  # query on both orgs to see that the definition committed successfully
  queryCommitted 1
  queryCommitted 2

  # Invoke the chaincode - this does require that the chaincode have the 'initLedger'
  # method defined
  if [ "$CC_INIT_FCN" = "NA" ]; then
    infoln "Chaincode initialization is not required"
  else
    chaincodeInvokeInit 1
  fi
}
##################################