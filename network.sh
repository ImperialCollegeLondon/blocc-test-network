#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script brings up a Hyperledger Fabric network for testing smart contracts
# and applications. The test network consists of two organizations with one
# peer each, and a single node Raft ordering service. Users can also use this
# script to create a channel deploy a chaincode on the channel
#
# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
#
# However using PWD in the path has the side effect that location that
# this script is run from is critical. To ease this, get the directory
# this script is actually in and infer location from there. (putting first)

ROOTDIR=$(cd "$(dirname "$0")" && pwd)
export PATH=${ROOTDIR}/../bin:${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=${PWD}/../blocc-pi-setup/fabric/config
export VERBOSE=false

# push to the required directory & set a trap to go back if needed
pushd "${ROOTDIR}" >/dev/null || exit
trap "popd > /dev/null" EXIT

. scripts/utils.sh

: "${CONTAINER_CLI:="docker"}"
: "${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}"
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"

# Obtain CONTAINER_IDS and remove them
# This function is called when you bring a network down
function clearContainers() {
  infoln "Removing remaining containers"
  ${CONTAINER_CLI} rm -f "$(${CONTAINER_CLI} ps -aq --filter label=service=blocc-fabric)" 2>/dev/null || true
  ${CONTAINER_CLI} rm -f "$(${CONTAINER_CLI} ps -aq --filter name='dev-peer*')" 2>/dev/null || true
  ${CONTAINER_CLI} kill "$(${CONTAINER_CLI} ps -q --filter name=ccaas)" 2>/dev/null || true
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
  infoln "Removing generated chaincode docker images"
  ${CONTAINER_CLI} image rm -f "$(${CONTAINER_CLI} images -aq --filter reference='dev-peer*')" 2>/dev/null || true
}

# Versions of fabric known not to work with the test network
NONWORKING_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

# Do some basic sanity checking to make sure that the appropriate versions of fabric
# binaries/images are available. In the future, additional checking for the presence
# of go or other items could be added.
function checkPrereqs() {
  ## Check if your have cloned the peer binaries and configuration files.
  peer version >/dev/null 2>&1

  if [[ $? -ne 0 || ! -d "../blocc-pi-setup" ]]; then
    # TODO: provide directions for how to fix
    errorln "BLOCC fabric binaries and blocc-pi-setup/ files not found.."
    exit 1
  fi
  # use the fabric tools container to see if the samples and binaries match your
  # docker images
  LOCAL_VERSION=$(peer version | sed -ne 's/^ Version: //p')
  DOCKER_IMAGE_VERSION=$(${CONTAINER_CLI} run --rm ghcr.io/imperialcollegelondon/fabric-tools:bloccprotocol-release peer version | sed -ne 's/^ Version: //p')

  infoln "LOCAL_VERSION=$LOCAL_VERSION"
  infoln "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    warnln "Local fabric binaries and docker images are out of sync. This may cause problems."
  fi

  for UNSUPPORTED_VERSION in $NONWORKING_VERSIONS; do
    if infoln "$LOCAL_VERSION" | grep -q "$UNSUPPORTED_VERSION"; then
      fatalln "Local Fabric binary version of $LOCAL_VERSION does not match the versions supported by the test network."
    fi

    if infoln "$DOCKER_IMAGE_VERSION" | grep -q "$UNSUPPORTED_VERSION"; then
      fatalln "Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match the versions supported by the test network."
    fi
  done
}

# Before you can bring up a network, each organization needs to generate the crypto
# material that will define that organization on the network. Because Hyperledger
# Fabric is a permissioned blockchain, each node and user on the network needs to
# use certificates and keys to sign and verify its actions. In addition, each user
# needs to belong to an organization that is recognized as a member of the network.
# You can use the Cryptogen tool or Fabric CAs to generate the organization crypto
# material.

# By default, the sample network uses cryptogen. Cryptogen is a tool that is
# meant for development and testing that can quickly create the certificates and keys
# that can be consumed by a Fabric network. The cryptogen tool consumes a series
# of configuration files for each organization in the "organizations/cryptogen"
# directory. Cryptogen uses the files to generate the crypto  material for each
# org in the "organizations" directory.

# You can also use Fabric CAs to generate the crypto material. CAs sign the certificates
# and keys that they generate to create a valid root of trust for each organization.
# The script uses Docker Compose to bring up three CAs, one for each peer organization
# and the ordering organization. The configuration file for creating the Fabric CA
# servers are in the "organizations/fabric-ca" directory. Within the same directory,
# the "registerEnroll.sh" script uses the Fabric CA client to create the identities,
# certificates, and MSP folders that are needed to create the test network in the
# "organizations/ordererOrganizations" directory.

# Create Organization crypto material using cryptogen or CAs
function createOrgs() {
  if [ -d "organizations/peerOrganizations" ]; then
    rm -Rf organizations/peerOrganizations && rm -Rf organizations/ordererOrganizations
  fi

  # Create crypto material using cryptogen
  if [ "$CRYPTO" == "cryptogen" ]; then
    
    if ! which cryptogen; then
      fatalln "cryptogen tool not found. exiting"
    fi
    infoln "Generating certificates using cryptogen tool"

    infoln "Creating organisation Identities"

    set -x
    cryptogen generate --config=../blocc-pi-setup/fabric/config/crypto-config.yaml --output="organizations"
    res=$?
    { set +x; } 2>/dev/null
    if [ $res -ne 0 ]; then
      fatalln "Failed to generate certificates..."
    fi

  fi

  # NOTE: disabled CCP generation- seems to have no use currently
}

# Once you create the organization crypto material, you need to create the
# genesis block of the application channel.

# The configtxgen tool is used to create the genesis block. Configtxgen consumes a
# "configtx.yaml" file that contains the definitions for the sample network. The
# genesis block is defined using the "TwoOrgsApplicationGenesis" profile at the bottom
# of the file. This profile defines an application channel consisting of our two Peer Orgs.
# The peer and ordering organizations are defined in the "Profiles" section at the
# top of the file. As part of each organization profile, the file points to the
# location of the MSP directory for each member. This MSP is used to create the channel
# MSP that defines the root of trust for each organization. In essence, the channel
# MSP allows the nodes and users to be recognized as network members.
#
# If you receive the following warning, it can be safely ignored:
#
# [bccsp] GetDefault -> WARN 001 Before using BCCSP, please call InitFactories(). Falling back to bootBCCSP.
#
# You can ignore the logs regarding intermediate certs, we are not using them in
# this crypto implementation.

# After we create the org crypto material and the application channel genesis block,
# we can now bring up the peers and ordering service. By default, the base
# file for creating the network is "docker-compose-test-net.yaml" in the ``docker``
# folder. This file defines the environment variables and file mounts that
# point the crypto material and genesis block that were created in earlier.

# Bring up the peer and orderer nodes using docker compose.
function networkUp() {
  checkPrereqs

  # generate artifacts if they don't exist
  if [ ! -d "organizations/peerOrganizations" ]; then
    createOrgs
  fi

  COMPOSE_FILES="-f compose/${COMPOSE_FILE_BASE}"

  DOCKER_SOCK="${DOCKER_SOCK}" ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} up -d 2>&1

  if ! $CONTAINER_CLI ps -a; then
    fatalln "Unable to start network"
  fi
}

# call the script to create the channel, join the peers of org1 and org2,
# and then update the anchor peers for each organization
function createChannel() {
  # Bring up the network if it is not already up.
  bringUpNetwork="false"

  if ! $CONTAINER_CLI info >/dev/null 2>&1; then
    fatalln "$CONTAINER_CLI network is required to be running to create a channel"
  fi

  # check if all containers are present
  CONTAINERS=($($CONTAINER_CLI ps | grep ghcr.io/imperialcollegelondon/ | awk '{print $2}'))
  len=${#CONTAINERS[@]}

  # NOTE: should be changed accordingly when scaling up
  EXPECTED_CONTAINER_NUM=5

  if [[ $len -ge $EXPECTED_CONTAINER_NUM ]] && [[ ! -d "organizations/peerOrganizations" ]]; then
    echo "Bringing network down to sync certs with containers"
    networkDown
  fi

  [[ $len -lt $EXPECTED_CONTAINER_NUM ]] || [[ ! -d "organizations/peerOrganizations" ]] && bringUpNetwork="true" || echo "Network Running Already"

  if [ $bringUpNetwork == "true" ]; then
    infoln "Bringing up network"
    networkUp
  fi

  # now run the script that creates a channel. This script uses configtxgen once
  # to create the channel creation transaction and the anchor peer updates.
  scripts/createChannel.sh "$CHANNEL_LEADER_NUM" "$CLI_DELAY" "$MAX_RETRY" $VERBOSE
}

## Call the script to deploy a chaincode to the channel
function deployCC() {
  if ! scripts/deployCC.sh "$CHANNEL_LEADER_NUM" "$CC_NAME" "$CC_SRC_PATH" "$CC_SRC_LANGUAGE" "$CC_VERSION" "$CC_SEQUENCE" "$CC_INIT_FCN" "$CC_END_POLICY" "$CC_COLL_CONFIG" "$CLI_DELAY" "$MAX_RETRY" $VERBOSE; then
    fatalln "Deploying chaincode failed"
  fi
}

# Tear down running network
function networkDown() {

  COMPOSE_FILES="-f compose/${COMPOSE_FILE_BASE}"

  if [ "${CONTAINER_CLI}" == "docker" ]; then
    DOCKER_SOCK=$DOCKER_SOCK ${CONTAINER_CLI_COMPOSE} ${COMPOSE_FILES} down --volumes --remove-orphans
  else
    fatalln "Container CLI  ${CONTAINER_CLI} not supported"
  fi

  # FIXME: may be fixed later - not prioritised
  # Don't remove the generated artifacts -- note, the ledgers are always removed
  if [ "$MODE" != "restart" ]; then
    #Cleanup the chaincode containers
    clearContainers
    #Cleanup images
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf system-genesis-block/*.block organizations/peerOrganizations organizations/ordererOrganizations'
    # remove channel and script artifacts
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt *.tar.gz'
    # remove docker container persistence
    ${CONTAINER_CLI} run --rm -v "$(pwd):/data" busybox sh -c 'cd /data && rm -rf production'
  fi
}

# Using crpto vs CA. default is cryptogen
CRYPTO="cryptogen"
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
MAX_RETRY=5
# default for delay between commands
CLI_DELAY=3
# channel name defaults to "channel5"
CHANNEL_LEADER_NUM="5"
# chaincode name defaults to "NA"
CC_NAME="NA"
# chaincode path defaults to "NA"
CC_SRC_PATH="NA"
# collection configuration defaults to "NA"
CC_COLL_CONFIG="NA"
# chaincode init function defaults to "NA"
CC_INIT_FCN="NA"
# use this as the default docker-compose yaml definition
COMPOSE_FILE_BASE=compose-test-net.yaml
# chaincode language defaults to "NA"
CC_SRC_LANGUAGE="NA"
# Chaincode version
CC_VERSION="1.0"
# Chaincode definition sequence
CC_SEQUENCE=1
# default database
DATABASE="leveldb"

# Get docker sock path from environment variable
SOCK="${DOCKER_HOST:-/var/run/docker.sock}"
DOCKER_SOCK="${SOCK##unix://}"

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]]; then
  printHelp
  exit 0
else
  MODE=$1
  shift
fi

# parse a createChannel subcommand if used
if [[ $# -ge 1 ]]; then
  key="$1"
  if [[ "$key" == "createChannel" ]]; then
    export MODE="createChannel"
    shift
  fi
fi

# parse flags

while [[ $# -ge 1 ]]; do
  key="$1"
  case $key in
  -h)
    printHelp "$MODE"
    exit 0
    ;;
  -c)
    CHANNEL_LEADER_NUM="$2"
    shift
    ;;
  -r)
    MAX_RETRY="$2"
    shift
    ;;
  -d)
    CLI_DELAY="$2"
    shift
    ;;
  -s)
    DATABASE="$2"
    shift
    ;;
  -ccl)
    CC_SRC_LANGUAGE="$2"
    shift
    ;;
  -ccn)
    CC_NAME="$2"
    shift
    ;;
  -ccv)
    CC_VERSION="$2"
    shift
    ;;
  -ccs)
    CC_SEQUENCE="$2"
    shift
    ;;
  -ccp)
    CC_SRC_PATH="$2"
    shift
    ;;
  -ccep)
    CC_END_POLICY="$2"
    shift
    ;;
  -cccg)
    CC_COLL_CONFIG="$2"
    shift
    ;;
  -cci)
    CC_INIT_FCN="$2"
    shift
    ;;
  -verbose)
    VERBOSE=true
    ;;
  *)
    errorln "Unknown flag: $key"
    printHelp
    exit 1
    ;;
  esac
  shift
done

# Are we generating crypto material with this command?
if [ ! -d "organizations/peerOrganizations" ]; then
  CRYPTO_MODE="with crypto from '${CRYPTO}'"
else
  CRYPTO_MODE=""
fi

# Determine mode of operation and printing out what we asked for
if [ "$MODE" == "up" ]; then
  infoln "Starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE}' ${CRYPTO_MODE}"
  networkUp
elif [ "$MODE" == "createChannel" ]; then
  infoln "Creating channel 'channel${CHANNEL_LEADER_NUM}'."
  infoln "If network is not up, starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE} ${CRYPTO_MODE}"
  createChannel
elif [ "$MODE" == "down" ]; then
  infoln "Stopping network"
  networkDown
elif [ "$MODE" == "restart" ]; then
  infoln "Restarting network"
  networkDown
  networkUp
elif [ "$MODE" == "deployCC" ]; then
  infoln "deploying chaincode on channel '${CHANNEL_LEADER_NUM}'"
  deployCC
elif [ "$MODE" == "deployCCAAS" ]; then
  infoln "deploying chaincode-as-a-service on channel '${CHANNEL_LEADER_NUM}'"
  deployCCAAS
else
  printHelp
  exit 1
fi
