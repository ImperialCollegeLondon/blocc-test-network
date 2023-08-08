#!/bin/bash

# imports  
. scripts/envVar.sh
. scripts/utils.sh

CHANNEL_NAME="$1"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
: "${CHANNEL_NAME:="channel5"}"
: "${DELAY:="3"}"
: "${MAX_RETRY:="5"}"
: "${VERBOSE:="false"}"

: "${CONTAINER_CLI:="docker"}"
: "${CONTAINER_CLI_COMPOSE:="${CONTAINER_CLI}-compose"}"
infoln "Using ${CONTAINER_CLI} and ${CONTAINER_CLI_COMPOSE}"

if [ ! -d "channel-artifacts" ]; then
	mkdir channel-artifacts
fi

createChannelGenesisBlock() {
	if ! which configtxgen; then
		fatalln "configtxgen tool not found."
	fi
	PROFILE=$1
	set -x
	configtxgen -profile "${PROFILE}" -outputBlock ./channel-artifacts/"${CHANNEL_NAME}".block -channelID "$CHANNEL_NAME"
	res=$?
	{ set +x; } 2>/dev/null
  verifyResult $res "Failed to generate channel configuration transaction..."
}

createChannel() {
	# NOTE: a random choice, can any peer
	setGlobals 5
	# Poll in case the raft leader is not set yet
	local rc=1
	local COUNTER=1
	while [ $rc -ne 0 ] && [ "$COUNTER" -lt "$MAX_RETRY" ]; do
		sleep "$DELAY"
		set -x
		# TODO: make orderer variable
		osnadmin channel join --channelID "$CHANNEL_NAME" --config-block ./channel-artifacts/"${CHANNEL_NAME}".block -o localhost:5053 --ca-file "$ORDERER_CA" --client-cert "$ORDERER_ADMIN_TLS_SIGN_CERT" --client-key "$ORDERER_ADMIN_TLS_PRIVATE_KEY" >&log.txt
		res=$?
		{ set +x; } 2>/dev/null
		rc=$res
		COUNTER=$((COUNTER + 1))
	done
	cat log.txt
	verifyResult $res "Channel creation failed"
}

# joinChannel ORG
joinChannel() {
  ORG=$1
  setGlobals "$ORG"
	local rc=1
	local COUNTER=1
	## Sometimes Join takes time, hence retry
	while [ $rc -ne 0 ] && [ "$COUNTER" -lt "$MAX_RETRY" ]; do
		sleep "$DELAY"
		set -x
		peer channel join -b "$BLOCKFILE" >&log.txt
		res=$?
		{ set +x; } 2>/dev/null
			rc=$res
			COUNTER=$((COUNTER + 1))
	done
	cat log.txt
	verifyResult $res "After $MAX_RETRY attempts, peer0.org${ORG} has failed to join channel '$CHANNEL_NAME' "
}

setAnchorPeer() {
  ORG=$1
  ${CONTAINER_CLI} exec cli ./scripts/setAnchorPeer.sh "$ORG" "$CHANNEL_NAME" 
}

FABRIC_CFG_PATH=${PWD}/configtx

## Create channel genesis block
infoln "Generating channel genesis block '${CHANNEL_NAME}.block'"
createChannelGenesisBlock Channel5Genesis

FABRIC_CFG_PATH=${PWD}/../blocc-pi-setup/fabric/config
BLOCKFILE="./channel-artifacts/${CHANNEL_NAME}.block"

## Create channel
infoln "Creating channel ${CHANNEL_NAME}"
createChannel
successln "Channel '$CHANNEL_NAME' created"

## Join all the peers to the channel
infoln "Joining container 5 peer to the channel..."
joinChannel 5
infoln "Joining container 6 peer to the channel..."
joinChannel 6

## Set the anchor peers for each org in the channel
infoln "Setting anchor peer for container 5..."
setAnchorPeer 5
infoln "Setting anchor peer for container 5..."
setAnchorPeer 6

successln "Channel '$CHANNEL_NAME' joined"
