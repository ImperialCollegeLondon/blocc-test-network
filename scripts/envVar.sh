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

# Set environment variables for the peer org
setGlobals() {
  local FABRIC_CONTAINER_NUM=""
  if [ -z "$OVERRIDE_ORG" ]; then
    FABRIC_CONTAINER_NUM=$1
  else
    FABRIC_CONTAINER_NUM="${OVERRIDE_ORG}"
  fi
  
  infoln "Using organization ${FABRIC_CONTAINER_NUM}"

  export CORE_PEER_ADDRESS=localhost:${FABRIC_CONTAINER_NUM}051
  export CORE_PEER_LOCALMSPID=Container${FABRIC_CONTAINER_NUM}MSP
  export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/container${FABRIC_CONTAINER_NUM}.blocc.doc.ic.ac.uk/users/Admin@container${FABRIC_CONTAINER_NUM}.blocc.doc.ic.ac.uk/msp
  export CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/organizations/peerOrganizations/container${FABRIC_CONTAINER_NUM}.blocc.doc.ic.ac.uk/tlsca/tlsca.container${FABRIC_CONTAINER_NUM}.blocc.doc.ic.ac.uk-cert.pem

  if [ "$VERBOSE" == "true" ]; then
    env | grep CORE
  fi
}

setOrdererGlobals() {
  CHANNEL_LEADER_NUM=$1
  export ORDERER_CA=${PWD}/organizations/ordererOrganizations/container${CHANNEL_LEADER_NUM}.blocc.doc.ic.ac.uk/tlsca/tlsca.container${CHANNEL_LEADER_NUM}.blocc.doc.ic.ac.uk-cert.pem
  export ORDERER_ADMIN_TLS_SIGN_CERT=${PWD}/organizations/ordererOrganizations/container${CHANNEL_LEADER_NUM}.blocc.doc.ic.ac.uk/orderers/orderer.container${CHANNEL_LEADER_NUM}.blocc.doc.ic.ac.uk/tls/server.crt
  export ORDERER_ADMIN_TLS_PRIVATE_KEY=${PWD}/organizations/ordererOrganizations/container${CHANNEL_LEADER_NUM}.blocc.doc.ic.ac.uk/orderers/orderer.container${CHANNEL_LEADER_NUM}.blocc.doc.ic.ac.uk/tls/server.key

}

# Set environment variables for use in the CLI container
setGlobalsCLI() {
  setGlobals $1

  local FABRIC_CONTAINER_NUM=""
  if [ -z "$OVERRIDE_ORG" ]; then
    FABRIC_CONTAINER_NUM=$1
  else
    FABRIC_CONTAINER_NUM="${OVERRIDE_ORG}"
  fi

  export CORE_PEER_ADDRESS=blocc-container${FABRIC_CONTAINER_NUM}:7051
}

# parsePeerConnectionParameters $@
# Helper function that sets the peer connection parameters for a chaincode
# operation
parsePeerConnectionParameters() {
  PEER_CONN_PARMS=()
  PEERS=""
  while [ "$#" -gt 0 ]; do
    setGlobals "$1"
    PEER="peer0.container$1"
    ## Set peer addresses
    if [ -z "$PEERS" ]
    then
	PEERS="$PEER"
    else
	PEERS="$PEERS $PEER"
    fi
    PEER_CONN_PARMS=("${PEER_CONN_PARMS[@]}" --peerAddresses "$CORE_PEER_ADDRESS")
    ## Set path to TLS certificate
    CA=${PWD}/organizations/peerOrganizations/container$1.blocc.doc.ic.ac.uk/tlsca/tlsca.container$1.blocc.doc.ic.ac.uk-cert.pem
    TLSINFO=(--tlsRootCertFiles ${CA})
    PEER_CONN_PARMS=("${PEER_CONN_PARMS[@]}" "${TLSINFO[@]}")
    # shift by one to get to the next organization
    shift
  done
}

verifyResult() {
  if [ "$1" -ne 0 ]; then
    fatalln "$2"
  fi
}
