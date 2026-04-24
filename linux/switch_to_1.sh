#!/bin/bash

# Device 1: e.g. MX Keys S connected to Unifying receiver
# Refer to the README.md for details on how to find the correct 
# values for your setup
KEYS_PID="C52B" # product ID of Unifying receiver
KEYS_USAGE_PAGE="0xFF00" # usage page for Unifying or Bolt receivers
KEYS_USAGE="0x0001" # usage for Unifying or Bolt receivers
KEYS_INDEX="0x01" # index of MX Keys S on the receiver
KEYS_COMMAND="0x0A,0x10" # command for switching channels
KEYS_CHANNEL="0x00" # target channel 1

# Switch Device 1 to channel 1
hidapitester --vidpid 046D:${KEYS_PID} --usagePage ${KEYS_USAGE_PAGE} --usage ${KEYS_USAGE} --open --length 20 --send-output 0x11,${KEYS_INDEX},${KEYS_COMMAND},${KEYS_CHANNEL}

# Device 2: e.g. MX Anywhere 3 connected to Unifying receiver
# Refer to the README.md for details on how to find the correct 
# values for your setup
MOUSE_PID="C52B" # product ID of Unifying receiver
MOUSE_USAGE_PAGE="0xFF00" # usage page for Unifying or Bolt receivers
MOUSE_USAGE="0x0001" # usage for Unifying or Bolt receivers
MOUSE_INDEX="0x02" # index of MX Anywhere 3 on the receiver
MOUSE_COMMAND="0x0A,0x10" # command for switching channels
MOUSE_CHANNEL="0x00" # target channel 1

# Switch Device 2 to channel 1
hidapitester --vidpid 046D:${MOUSE_PID} --usagePage ${MOUSE_USAGE_PAGE} --usage ${MOUSE_USAGE} --open --length 20 --send-output 0x11,${MOUSE_INDEX},${MOUSE_COMMAND},${MOUSE_CHANNEL}
