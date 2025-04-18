#!/bin/bash

# Configuration variables
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"
BACKUP_DIR="/backup/cassandra"
RESTORE_DIR="/tmp/cassandra_restore"
LOG_FILE="/var/log/cassandra/restore.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Function to list available backups
list_backups() {
    echo "Available backups:"
    ls -lt $BACKUP_DIR/*.tar.gz | awk '{print $9}' | xargs -n1 basename
}

# Function to check if Cassandra is running
check_cassandra() {
    if nodetool status >/dev/null 2>&1; then
        log "WARNING: Cassandra is running. It's recommended to stop Cassandra before restore."
        read -p "Do you want to stop Cassandra now? (y/n): " choice
        if [ "$choice" = "y" ]; then
            nodetool stopdaemon
            systemctl stop cassandra
            sleep 10
        else
            log "ERROR: Please stop Cassandra manually before proceeding"
            exit 1
        fi
    fi
}

# Function to extract backup
extract_backup() {
    local backup_file=$1
    log "Extracting backup: $backup_file"
    
    # Clean and create restore directory
    rm -rf $RESTORE_DIR
    mkdir -p $RESTORE_DIR
    
    # Extract the backup
    tar -xzf "$BACKUP_DIR/$backup_file" -C $RESTORE_DIR
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to extract backup"
        exit 1
    fi
}

# Function to restore schema
restore_schema() {
    local backup_name=$(echo $1 | sed 's/.tar.gz//')
    local schema_file="$BACKUP_DIR/schema_$backup_name.cql"
    
    log "Starting schema restore"

    chown -R cassandra:cassandra $CASSANDRA_DATA_DIR
    
    # Start Cassandra temporarily if it's not running
    if ! nodetool status >/dev/null 2>&1; then
        systemctl start cassandra
        sleep 30
    fi
    
    # Restore schema
    if [ -f "$schema_file" ]; then
        log "Restoring schema from $schema_file"
        cqlsh -u cassandra -p cassandra `hostname` -f "$schema_file"
        if [ $? -ne 0 ]; then
            log "ERROR: Schema restore failed"
        fi
    else
        log "WARNING: Schema file not found"
    fi
    
    # Stop Cassandra again for data restore
    systemctl stop cassandra
    sleep 10
}

# Function to restore data
restore_data() {
    local backup_name=$(echo $1 | sed 's/.tar.gz//')
    log "Starting data restore"
    
    # Clear existing data
    log "Clearing existing data directories"
    rm -rf $CASSANDRA_DATA_DIR/*
    
    # Iterate through keyspaces and tables in backup
    find $RESTORE_DIR/$backup_name -mindepth 2 -maxdepth 2 -type d | while read table_dir; do
        keyspace=$(basename $(dirname "$table_dir"))
        table=$(basename "$table_dir")
        
        # Create destination directory
        dest_dir="$CASSANDRA_DATA_DIR/$keyspace/$table"
        mkdir -p "$dest_dir"
        
        # Copy data files
        cp -r "$table_dir"/* "$dest_dir/"
        
        log "Restored $keyspace/$table"
    done

    chown -R cassandra:cassandra $CASSANDRA_DATA_DIR
}

# Function to verify restore
verify_restore() {
    log "Starting Cassandra"
    systemctl start cassandra
    sleep 30
    
    if nodetool status | grep -q "UN"; then
        log "Cassandra started successfully"
        log "Running nodetool repair"
        nodetool repair -pr
    else
        log "ERROR: Cassandra failed to start properly"
        exit 1
    fi
}

# Main restore process
main() {
    if [ -z "$1" ]; then
        list_backups
        echo "Usage: $0 <backup_file.tar.gz>"
        exit 1
    fi
    
    local backup_file=$1
    
    if [ ! -f "$BACKUP_DIR/$backup_file" ]; then
        log "ERROR: Backup file not found: $backup_file"
        list_backups
        exit 1
    fi
    
    log "Starting restore process for backup: $backup_file"
    
    # Confirmation prompt
    read -p "This will overwrite existing data. Are you sure? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        log "Restore cancelled by user"
        exit 1
    fi
    
    check_cassandra
    extract_backup "$backup_file"
    restore_schema "$backup_file"
    restore_data "$backup_file"
    verify_restore
    
    log "Restore process completed"
    log "Please verify your data integrity"
}

# Execute main function
main "$@"