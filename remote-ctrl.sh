#!/bin/bash

if [ -z "$SSH_HOST" ]
then
    echo "\$SSH_HOST is empty"
    exit 1
fi

if [ -z "$SSH_FORWARD_PORT" ]
then
    echo "\$SSH_FORWARD_PORT is empty"
    exit 1
fi

if [ -z "$SSH_USERNAME" ]
then
    echo "\$SSH_USERNAME is empty"
    exit 1
fi

if [ -z "$SSH_PRIVATE_KEY" ]
then
    echo "\$SSH_PRIVATE_KEY is empty"
    exit 1
fi

if [ -z "$SSH_PORT" ]
then
    SSH_PORT=22
fi

PRIVATE_KEY_FILE=/tmp/temp_ssh_key
echo -e "$SSH_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
chmod 600 "$PRIVATE_KEY_FILE"

if [ -z "$SSH_HOST_KEY" ]
then
    echo "\$SSH_HOST_KEY is empty"
else
    KNOWN_HOSTS_FILE=~/.ssh/known_hosts
    KNOWN_HOST="$SSH_HOST $SSH_HOST_KEY"
    if [ ! -f "$KNOWN_HOSTS_FILE" ] || ! grep -Fxq "$KNOWN_HOST" "$KNOWN_HOSTS_FILE" 
    then
        mkdir -p ~/.ssh
        echo "$KNOWN_HOST" >> "$KNOWN_HOSTS_FILE"
    fi
fi

if [ -z "$SSH_AUTH_KEY" ]
then
    echo "\$SSH_AUTH_KEY is empty"
else
    AUTHORIZED_KEYS_FILE=~/.ssh/authorized_keys
    if [ ! -f "$AUTHORIZED_KEYS_FILE" ] || ! grep -Fxq "$SSH_AUTH_KEY" "$AUTHORIZED_KEYS_FILE" 
    then
        mkdir -p ~/.ssh
        echo "$SSH_AUTH_KEY" >> "$AUTHORIZED_KEYS_FILE"
    fi
fi

ssh -o "ExitOnForwardFailure yes" -N -R $SSH_FORWARD_PORT:localhost:$SSH_PORT $SSH_USERNAME@$SSH_HOST -i $PRIVATE_KEY_FILE &
sleep 2
rm $PRIVATE_KEY_FILE
