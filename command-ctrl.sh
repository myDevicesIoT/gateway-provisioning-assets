#!/bin/sh


remote_ctrl() { 
    if [ -z "$SSH_HOST" ]; then
        echo "\$SSH_HOST is empty"
        exit 1
    fi

    if [ -z "$SSH_FORWARD_PORT" ]; then
        echo "\$SSH_FORWARD_PORT is empty"
        exit 1
    fi

    if [ -z "$SSH_USERNAME" ]; then
        echo "\$SSH_USERNAME is empty"
        exit 1
    fi

    if [ -z "$SSH_PRIVATE_KEY" ]; then
        echo "\$SSH_PRIVATE_KEY is empty"
        exit 1
    fi

    if [ -z "$SSH_LOCAL_PORT" ]; then
        SSH_LOCAL_PORT=22
    fi

    if [ -z "$SSH_REMOTE_PORT" ]; then
        SSH_REMOTE_PORT=22
    fi

    PRIVATE_KEY_FILE=/tmp/temp_ssh_key
    echo -e "$SSH_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
    chmod 600 "$PRIVATE_KEY_FILE"

    if [ -z "$SSH_HOST_KEY" ]; then
        echo "\$SSH_HOST_KEY is empty"
    else
        KNOWN_HOSTS_FILE=~/.ssh/known_hosts
        KNOWN_HOST="$SSH_HOST $SSH_HOST_KEY"
        if [ ! -f "$KNOWN_HOSTS_FILE" ] || ! grep -Fxq "$KNOWN_HOST" "$KNOWN_HOSTS_FILE"; then
            mkdir -p ~/.ssh
            echo "$KNOWN_HOST" >> "$KNOWN_HOSTS_FILE"
        fi
    fi

    if [ -z "$SSH_AUTH_KEY" ]; then
        echo "\$SSH_AUTH_KEY is empty"
    else
        AUTHORIZED_KEYS_FILE=~/.ssh/authorized_keys
        if [ ! -f "$AUTHORIZED_KEYS_FILE" ] || ! grep -Fxq "$SSH_AUTH_KEY" "$AUTHORIZED_KEYS_FILE"; then
            mkdir -p ~/.ssh
            echo "$SSH_AUTH_KEY" >> "$AUTHORIZED_KEYS_FILE"
        fi
    fi

    if [ "$SSHD_FORCE_PUBKEY_AUTH" == "true" ]; then
        echo "Starting sshd with publickey authentication"
        $(which sshd) -p $SSH_LOCAL_PORT -o "PubkeyAuthentication yes"
    fi
    ssh -o "ExitOnForwardFailure yes" -N -R $SSH_FORWARD_PORT:localhost:$SSH_LOCAL_PORT $SSH_USERNAME@$SSH_HOST -p $SSH_REMOTE_PORT -i $PRIVATE_KEY_FILE &
    sleep 2
    rm $PRIVATE_KEY_FILE
}

update() {
    if [ -z "$UPDATE_URL" ]; then
        echo "\$UPDATE_URL is empty"
        exit 1
    fi

    if [ "$UPDATE_FILE_MODE" != "" ] && [ -z "$(echo "$UPDATE_FILE_MODE" | grep -E '^[0-7]{3,4}$')" ]; then
        echo "\$UPDATE_FILE_MODE is not valid"
        exit 1
    fi    

    UPDATE_FILE_PATH=/tmp/$(basename $UPDATE_URL)
    if [ "$UPDATE_FILE_PATH" != "/tmp/" ]; then
        echo "Downloading $UPDATE_URL"
        curl -s -f $UPDATE_URL --output $UPDATE_FILE_PATH
        RESULT=$?
        if test "$RESULT" == "77" && ! test -f /etc/ssl/certs/ca-certificates.crt; then
            echo "Download failed, attempting to update certs and retry"
            update-ca-certificates
            curl -s -f $UPDATE_URL --output $UPDATE_FILE_PATH
            RESULT=$?
        fi
        if test "$RESULT" != "0"; then
            echo "Download failed with: $RESULT"
            rm -f $UPDATE_FILE_PATH
            exit $RESULT
        fi

        echo "Verifying checksum"
        DOWNLOAD_MD5=$(md5sum "$UPDATE_FILE_PATH" | cut -d " " -f1)
        if [ $DOWNLOAD_MD5 == $UPDATE_MD5 ]; then
            echo "Checksum matches"
            if [ "$UPDATE_TYPE" == "file" ]; then
                if [ "$UPDATE_DEST" != "" ]; then
                    echo "Moving file to $UPDATE_DEST"
                    DEST_DIR=$(dirname $UPDATE_DEST)
                    mkdir -p $DEST_DIR
                    mv -f $UPDATE_FILE_PATH $UPDATE_DEST
                    if [ "$UPDATE_FILE_MODE" != "" ]; then
                        #If the specified file mode is valid, set it
                        chmod $UPDATE_FILE_MODE $UPDATE_DEST
                    fi
                    exit $?
                fi
            fi

            echo "Installing $UPDATE_FILE_PATH"
            UPDATE_OPTIONS=""
            FORCE_REINSTALL=$(echo "$FORCE_REINSTALL" | tr '[:upper:]' '[:lower:]')
            if [ "$FORCE_REINSTALL" == "true" ]; then
                UPDATE_OPTIONS="--force-reinstall"
            fi
            echo "opkg install $UPDATE_FILE_PATH $UPDATE_OPTIONS"
            opkg install $UPDATE_FILE_PATH $UPDATE_OPTIONS
        else
            echo "Checksum does not match"
        fi

        echo "Deleting $UPDATE_FILE_PATH"
        rm -f $UPDATE_FILE_PATH
    fi
}

case "$1" in
    "remote-ctrl")
    remote_ctrl
        ;;
    "update")
    update
        ;;
    *)
        ## If no parameters are given, print which are available.
        echo "Usage: $0 {remote-ctrl|update}"
        exit 1
    ;;
esac