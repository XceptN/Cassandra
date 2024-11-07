#!/bin/bash

# Configuration variables
BACKUP_BASE_DIR="/backup/cassandra"
LOG_DIR="/var/log/cassandra"
RESTORE_DIR="/tmp/cassandra_restore"
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"
CASSANDRA_CONFIG_DIR="/etc/cassandra"

# Array of nodes in the cluster - MODIFY THESE
SEED_NODES=("192.168.56.15" "192.168.56.16")
ALL_NODES=("192.168.56.15" "192.168.56.16" "192.168.56.17")
LOCAL_NODE=$(hostname -i)

# Create required directories
mkdir -p "$RESTORE_DIR"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/cluster_restore.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if current node is a seed node
is_seed_node() {
    echo "${SEED_NODES[@]}" | grep -q "$LOCAL_NODE"
    return $?
}

# Function to list available backups
list_backups() {
    log "Available backups for node ${LOCAL_NODE}:"
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type f -name "cluster_backup_*_${LOCAL_NODE}.tar.gz" -printf "%T@ %p\n" | \
        sort -nr | cut -d' ' -f2- | while read -r backup; do
        echo "$(basename "$backup")"
    done
}

# Function to validate backup files
validate_backup() {
    local backup_date=$1
    local backup_file="${BACKUP_BASE_DIR}/cluster_backup_${backup_date}_${LOCAL_NODE}.tar.gz"
    
    if [ ! -f "$backup_file" ]; then
        log "ERROR: Backup file not found: $backup_file"
        return 1
    fi
    
    log "Validating backup file: $backup_file"
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        log "ERROR: Backup file is corrupted"
        return 1
    fi
    
    return 0
}

# Function to coordinate cluster shutdown
stop_cluster() {
    log "Initiating cluster shutdown sequence"
    
    # Stop non-seed nodes first
    if ! is_seed_node; then
        log "Stopping non-seed node ${LOCAL_NODE}"
        nodetool drain
        nodetool stopdaemon
        systemctl stop cassandra
        sleep 30
    else
        # Wait for non-seed nodes to stop
        log "Waiting for non-seed nodes to stop"
        sleep 60
        
        log "Stopping seed node ${LOCAL_NODE}"
        nodetool drain
        nodetool stopdaemon
        systemctl stop cassandra
        sleep 30
    fi
}

# Function to extract and prepare backup
prepare_restore() {
    local backup_date=$1
    local backup_file="${BACKUP_BASE_DIR}/cluster_backup_${backup_date}_${LOCAL_NODE}.tar.gz"
    
    log "Preparing restore from backup: $backup_file"
    
    # Clean restore directory
    rm -rf "${RESTORE_DIR:?}/"*
    
    # Extract backup
    if ! tar -xzf "$backup_file" -C "$RESTORE_DIR"; then
        log "ERROR: Failed to extract backup"
        exit 1
    fi
}

# Function to restore schema (seed nodes only)
restore_schema() {
    local backup_date=$1
    
    if is_seed_node; then
        # Start Cassandra temporarily for schema restore
        log "Starting Cassandra temporarily"        
        chown -R cassandra:cassandra $CASSANDRA_DATA_DIR
        
        systemctl start cassandra
        sleep 60
        
        log "Restoring schema on seed node ${LOCAL_NODE}"

        # Apply schema
        local schema_file="${RESTORE_DIR}/cluster_backup_${backup_date}/${LOCAL_NODE}/schema.cql"
        if [ -f "$schema_file" ]; then
            log "Applying schema from $schema_file"
            if ! cqlsh -u cassandra -p cassandra $LOCAL_NODE -f "$schema_file"; then
                log "ERROR: Schema restore failed"
            fi
        else
            log "ERROR: Schema file $schema_file not found"
            exit 1
        fi
        
        # Stop Cassandra again for data restore
        nodetool drain
        nodetool stopdaemon
        systemctl stop cassandra
        sleep 30
    fi
}

# Function to restore data files
restore_data() {
    local backup_date=$1
    log "Restoring data files on ${LOCAL_NODE}"
    
    # Clear existing data
    log "Clearing existing data directory"
    rm -rf "${CASSANDRA_DATA_DIR:?}/"*
    
    # Restore data files
    local backup_path="${RESTORE_DIR}/cluster_backup_${backup_date}/${LOCAL_NODE}"
    find "$backup_path" -mindepth 2 -maxdepth 2 -type d | while read -r table_dir; do
        local keyspace=$(basename "$(dirname "$table_dir")")
        local table=$(basename "$table_dir")
        
        # Skip system keyspaces on non-seed nodes
        if ! is_seed_node && [[ "$keyspace" == "system"* ]]; then
            continue
        fi
        
        log "Restoring $keyspace/$table"
        mkdir -p "${CASSANDRA_DATA_DIR}/${keyspace}/${table}"
        cp -r "${table_dir}"/* "${CASSANDRA_DATA_DIR}/${keyspace}/${table}/"
    done

    chown -R cassandra:cassandra $CASSANDRA_DATA_DIR
}

# Function to start cluster in correct order
start_cluster() {
    if is_seed_node; then
        log "Starting seed node ${LOCAL_NODE}"
        systemctl start cassandra
        
        # Wait for node to be fully up
        local retries=0
        while ! nodetool status | grep -q "UN"; do
            log "Waiting for seed node to start..."
            sleep 10
            ((retries++))
            if [ $retries -gt 30 ]; then
                log "ERROR: Seed node failed to start"
                exit 1
            fi
        done
    else
        # Non-seed nodes wait for seeds to be up
        log "Waiting for seed nodes to be up"
        sleep 120
        
        log "Starting non-seed node ${LOCAL_NODE}"
        systemctl start cassandra
    fi
}

# Function to rebuild node
rebuild_node() {
    if ! is_seed_node; then
        log "Rebuilding node ${LOCAL_NODE}"
        
        # Wait for node to be fully up
        sleep 60
        
        # Start rebuild process
        nodetool rebuild
        
        # Monitor rebuild progress
        while nodetool netstats | grep -q "Rebuild"; do
            log "Rebuild in progress..."
            sleep 300
        done
    fi
}

# Function to verify restore
verify_restore() {
    log "Verifying restore on ${LOCAL_NODE}"
    
    # Check node status
    if ! nodetool status | grep -q "UN"; then
        log "ERROR: Node is not up normally"
        return 1
    fi
    
    # Run repair with parallel threads
    log "Running repair with parallel threads"
    nodetool repair -pr -j 2
    
    # Verify token ranges
    log "Verifying token ranges"
    nodetool verify
    
    log "Restore verification completed on ${LOCAL_NODE}"
}

# Main restore process
main() {
    if [ $# -ne 1 ]; then
        log "Usage: $0 <backup_date (YYYYMMDD_HHMMSS)>"
        list_backups
        exit 1
    fi
    
    local backup_date=$1
    
    # Validate backup before proceeding
    if ! validate_backup "$backup_date"; then
        exit 1
    fi
    
    # Confirm restore
    echo "WARNING: This will restore the cluster to backup from $backup_date"
    echo "All existing data will be overwritten!"
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log "Restore cancelled by user"
        exit 1
    fi
    
    # Execute restore sequence
    stop_cluster
    prepare_restore "$backup_date"
    restore_schema "$backup_date"
    restore_data "$backup_date"
    start_cluster
    rebuild_node
    verify_restore
    
    log "Restore process completed on ${LOCAL_NODE}"
}

# Execute main function with error handling
main "$@" || {
    log "ERROR: Restore failed on ${LOCAL_NODE}"
    exit 1
}