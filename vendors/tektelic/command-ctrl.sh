#!/bin/sh

add_ssh_entry() {
    ENTRY=$1
    SSH_FILE=$2
    #Add the entry in both .ssh dirs since ssh checks different locations based on env variables and how it is launched, e.g. on boot vs. manually
    for DIR in ~root/.ssh $HOME/.ssh
    do
        if [ ! -f "$DIR/$SSH_FILE" ] || ! grep -Fxq "$ENTRY" "$DIR/$SSH_FILE"; then
            mkdir -p $DIR
            echo "$ENTRY" >> "$DIR/$SSH_FILE"
        fi
    done
}

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

    export PRIVATE_KEY_FILE=/tmp/temp_ssh_key
    echo -e "$SSH_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
    if command -v dropbearconvert &> /dev/null; then
        dropbearconvert openssh dropbear "$PRIVATE_KEY_FILE" "$PRIVATE_KEY_FILE"
    fi
    chmod 600 "$PRIVATE_KEY_FILE"

    if [ -z "$SSH_HOST_KEY" ]; then
        echo "\$SSH_HOST_KEY is empty"
    else
        KNOWN_HOST="$SSH_HOST $SSH_HOST_KEY"
        add_ssh_entry "$KNOWN_HOST" known_hosts
    fi

    if [ -z "$SSH_AUTH_KEY" ]; then
        echo "\$SSH_AUTH_KEY is empty"
    else
        add_ssh_entry "$SSH_AUTH_KEY" authorized_keys
    fi

    if [ "$SSHD_FORCE_PUBKEY_AUTH" == "true" ]; then
        echo "Starting sshd with publickey authentication"
        $(which sshd) -p $SSH_LOCAL_PORT -o "PubkeyAuthentication yes"
    fi
    ssh -o "ExitOnForwardFailure yes" -N -R $SSH_FORWARD_PORT:localhost:$SSH_LOCAL_PORT $SSH_USERNAME@$SSH_HOST -p $SSH_REMOTE_PORT -i $PRIVATE_KEY_FILE &
    sh -c 'sleep 10; rm $PRIVATE_KEY_FILE'
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
        if ( test "$RESULT" == "60" || test "$RESULT" == "77" ) && ! test -f /etc/ssl/certs/ca-certificates.crt; then
            echo "Download failed, attempting to update certs and retry"
            if command -v update-ca-certificates &> /dev/null; then
                update-ca-certificates
            else
                opkg update
                opkg install ca-certificates
                opkg upgrade ca-certificates
            fi
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

reboot_device() {
    /usr/bin/tektelic_reset
}

case "$1" in
    "remote-ctrl")
        remote_ctrl
        ;;
    "update")
        update
        ;;
    "reboot")
        reboot_device
        ;;
    *)
        ## If no parameters are given, print which are available.
        echo "Usage: $0 {remote-ctrl|update|reboot}"
        exit 1
    ;;
esac