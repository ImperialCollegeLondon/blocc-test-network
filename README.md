# BLOCC Test Network

This is a test network for the BLOCC project to simulate the deployed BLOCC network, making the development for relevant applications and chiancodes more convenient.

## Prerequisite

You should have...

- [blocc-pi-setup](https://github.com/ImperialCollegeLondon/blocc-pi-setup) project
- [BLOCC Hyperledger Fabric](https://github.com/ImperialCollegeLondon/blocc-fabric) installed
- Relevant chaincode source directories

...in a neighbouring directory, as in the following:

```shell
~/blocc
├── bin # BLOCC Fabric binaries
├── blocc-pi-setup # The actual configuration used on deployed network
├── blocc-temp-humidity-chaincode # Relevant chaincode source directories
├── blocc-test-network # **This project**
├── builders # BLOCC Fabric chaincode builders
└── config # BLOCC Fabric configurations
```

## Quick Start

You can bring up the BLOCC network and create a channel called `channel5` via

```shell
./network.sh up createChannel -c channel5
```

You can deploy a chaincode code `sensor_chaincode` via

```shell
./network.sh deployCC -ccn sensor_chaincode -ccp ~/blocc/blocc-temp-humidity-chaincode -ccl java -ccep "AND('Container5MSP.peer')"
```

> Note that: the signature policy is required as per the BLOCC protocol

For detail usage, please consult

```shell
./network.sh help
```
