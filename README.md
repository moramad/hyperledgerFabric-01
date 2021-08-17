# Hyperledger Fabric Project Template

Project template for hyperledger fabric with standarized directory structure. 

## Scenario
- 2 default organizations.
- 1 peer each nodes.
- support multi nodes.
- using script generator.

## Directory Tree
```
├── bin
├── config
│   ├── configtx.yaml
│   ├── core.yaml
│   └── orderer.yaml
├── dir-structure.txt
├── network
│   ├── configtx
│   │   └── configtx.yaml
│   ├── docker
│   │   ├── docker-compose-ca2.yaml
│   │   ├── docker-compose-ca.yaml
│   │   ├── docker-compose-couch2.yaml
│   │   ├── docker-compose-couch.yaml
│   │   ├── docker-compose-test-net2.yaml
│   │   └── docker-compose-test-net.yaml
│   ├── network.sh
│   ├── organizations
│   │   ├── ccp-template.json
│   │   ├── ccp-template.yaml
│   │   └── fabric-ca
│   │       ├── ordererOrg
│   │       │   └── fabric-ca-server-config.yaml
│   │       ├── org1
│   │       │   └── fabric-ca-server-config.yaml
│   │       └── org2
│   │           └── fabric-ca-server-config.yaml
│   ├── scripts
│   │   ├── configUpdate.sh
│   │   ├── envVar.sh
│   │   ├── functionCatalog.sh
│   │   ├── setAnchorPeer.sh
│   │   └── utils.sh
│   ├── start-sequence.sh
│   ├── system-genesis-block
│   └── test.sh
└── README.md
```