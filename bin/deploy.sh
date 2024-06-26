#!/usr/bin/env bash

source "$(dirname $0)/common.sh"

# Set up environment

setup_workspace() {
    log "Setting up workspace"

    mkdir -p "$WORKSPACE"
}

setup_temp_dir() {
    log "Setting up temporary directory"

    TEMP_DIR="$(mktemp -d)"
}

try_ossutil() {
    log "Trying to find existing ossutil from PATH"

    if type ossutil >/dev/null 2>&1; then
        OSSUTIL=ossutil

        log "Found existing ossutil"
        type ossutil
    else
        log "ossutil does not exist or is not executable"
    fi
}

setup_ossutil() {
    log "Setting up ossutil"

    if [[ "$OS_TYPE" == "windows" ]]; then
        OSSUTIL_EXTENSION=".exe"
    else
        OSSUTIL_EXTENSION=""
    fi
    OSSUTIL_DOWNLOAD_DIR="$TEMP_DIR"
    OSSUTIL_DOWNLOAD_DEST="ossutil.zip"
    OSSUTIL_BINARY="$WORKSPACE/ossutil$OSSUTIL_EXTENSION"
    OSSUTIL_CONFIG_FILE="$WORKSPACE/.ossutilconfig"
    OSSUTIL_OUTPUT_DIR="$TEMP_DIR/ossutil-output"
    OSSUTIL="$OSSUTIL_BINARY --config-file=$OSSUTIL_CONFIG_FILE"

    if [[ -f "$OSSUTIL_BINARY" ]]; then
        log "Using ossutil from cache"
    else
        log "Downloading ossutil"
        curl --create-dirs --fail --location --output "$OSSUTIL_DOWNLOAD_DIR/$OSSUTIL_DOWNLOAD_DEST" "$OSSUTIL_DOWNLOAD_URL"
        (cd "$OSSUTIL_DOWNLOAD_DIR" && unzip -o "$OSSUTIL_DOWNLOAD_DEST")
        mv "$OSSUTIL_DOWNLOAD_DIR/$OSSUTIL_SPEC/$OSSUTIL_EXECUTABLE_NAME" "$OSSUTIL_BINARY"
    fi
    chmod u+x "$OSSUTIL_BINARY"

    log "Configuring ossutil"
    CONFIG_OPTIONS=(
        "--output-dir=$OSSUTIL_OUTPUT_DIR"
    )
    if [[ "$OSS_ENDPOINT" != "" ]]; then
        CONFIG_OPTIONS+=(
            "--endpoint=$OSS_ENDPOINT"
        )
    else
        log "Error: 'oss-endpoint' is required but not provided"
        exit 1
    fi
    if [[ "$OSS_ACCESSKEY_ID" != "" ]]; then
        CONFIG_OPTIONS+=(
            "--access-key-id=$OSS_ACCESSKEY_ID"
        )
    fi
    if [[ "$OSS_ACCESSKEY_SECRET" != "" ]]; then
        CONFIG_OPTIONS+=(
            "--access-key-secret=$OSS_ACCESSKEY_SECRET"
        )
    fi
    if [[ "$OSS_STS_TOKEN" != "" ]]; then
        CONFIG_OPTIONS+=(
            "--sts-token=$OSS_STS_TOKEN"
        )
    fi
    $OSSUTIL config "${CONFIG_OPTIONS[@]}"
    chmod 600 "$OSSUTIL_CONFIG_FILE"
}

setup_environment() {
    start_group "Set up environment"

    setup_workspace
    setup_temp_dir
    if [[ "$FORCE_SETUP_OSSUTIL" == "" ]]; then
        find_ossutil
    fi
    if [[ "$OSSUTIL" == "" ]]; then
        setup_ossutil
    fi

    end_group
}

# Perform deployment

delete_existing_files() {
    log "Deleting existing files"
    $OSSUTIL rm \
        --recursive \
        --force \
        "$OSS_PATH"
}

remove_ignored_files() {
    log "Removing ignored files"
    BACKUP_DIR="$WORKSPACE/backup-$(date +%s)"
    mkdir -p "$BACKUP_DIR"
    shopt -s nullglob
    mv $IGNORED_PATTERNS "$BACKUP_DIR/" || true
    shopt -u nullglob
}

upload_files() {
    log "Uploading files"
    $OSSUTIL cp \
        --recursive \
        --update \
        "$LOCAL_PATH" \
        "$OSS_PATH" \
        --include \
        "$INCLUDE"
}

restore_ignored_files() {
    log "Restoring ignored files"
    shopt -s nullglob
    mv "$BACKUP_DIR"/{*,.[^.]*} ./ || true
    shopt -u nullglob
}

perform_deployment() {
    start_group "Perform deployment"

    if [[ "$DELETE_FIRST" == "true" ]]; then
        delete_existing_files
    fi
    remove_ignored_files
    upload_files
    restore_ignored_files

    end_group
}

# Clear environment

clear_credentials() {
    if [[ "$OSSUTIL_CONFIG_FILE" != "" ]]; then
        log "Removing configuration file"
        rm -f "$OSSUTIL_CONFIG_FILE"
    else
        log "Not removing configration file because it is not managed by this action"
    fi
}

clear_environment() {
    start_group "Clear environment"

    clear_credentials

    end_group
}

setup_environment
perform_deployment
clear_environment
