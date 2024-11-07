#!/bin/bash

# Configuration variables
BACKUP_BASE_DIR="/backup/cassandra"
LOG_DIR="/var/log/cassandra"
BACKUP_NAME="cluster_backup_$(date +%Y%m%d_%H%M%S)"
RETENTION_DAYS=7
PARALLEL_JOBS=2

# Array of nodes in the cluster - MODIFY THESE
SEED_NODES=("192.168.56.15" "192.168.56.16")
ALL_NODES=("192.168.56.15" "192.168.56.16" "192.168.56.17")
LOCAL_NODE=$(hostname -f)

# Create required directories
mkdir -p "${BACKUP_BASE_DIR}/${BACKUP_NAME}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/cluster_backup.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if current node is a seed node
is_seed_node() {
    echo "${SEED_NODES[@]}" | grep -q "$LOCAL_NODE"
    return $?
}

# Function to verify cluster health
check_cluster_health() {
    log "Checking cluster health..."
    
    # Check if all nodes are up and normal (UN)
    local unhealthy_nodes=0
    for node in "${ALL_NODES[@]}"; do
        if ! nodetool status 2>/dev/null | grep "$node" | grep -q "UN"; then
            log "WARNING: Node $node is not in UN state"
            ((unhealthy_nodes++))
        fi
    done
    
    if [ $unhealthy_nodes -gt 0 ]; then
        log "ERROR: $unhealthy_nodes nodes are not healthy. Aborting backup."
        exit 1
    fi
    
    # Check for pending compactions
    local pending_compactions=$(nodetool compactionstats | grep "pending tasks" | awk '{print $3}')
    if [ "$pending_compactions" -gt 0 ]; then
        log "WARNING: There are $pending_compactions pending compactions"
        read -p "Continue anyway? (y/n): " choice
        if [ "$choice" != "y" ]; then
            log "Backup aborted by user due to pending compactions"
            exit 1
        fi
    fi
}

# Function to backup schema (only on seed node)
backup_schema() {
    if is_seed_node; then
        log "Backing up schema on seed node ${LOCAL_NODE}"
        local schema_file="${BACKUP_BASE_DIR}/${BACKUP_NAME}/schema.cql"
        
        # Backup schema for each keyspace
        for keyspace in $(cqlsh -e "DESC KEYSPACES" | tr ' ' '\n' | grep -v "^$"); do
            log "Backing up schema for keyspace: $keyspace"
            cqlsh  -u cassandra -p cassandra $LOCAL_NODE -e "DESC KEYSPACE $keyspace" >> "$schema_file" 2>>$LOG_FILE
        done
        
        if [ $? -eq 0 ]; then
            log "Schema backup completed successfully"
        else
            log "ERROR: Schema backup failed"
            exit 1
        fi
    fi
}

# Function to clean up old snapshots
cleanup_old_snapshots() {
    log "Cleaning up old snapshots"
    
    # Remove old (older than RETENTION_DAYS) Cassandra snapshots
    # Calculate unix time msec RETENTION_DAYS ago
    DT=$(date +%s%3N)
    THRESHOLD=$(($DT-7*24*60*60*1000))
    TO_BE_CLEARED=$(nodetool listsnapshots | awk '{ print $1 }' | sort -u | grep -E '^[0-9]+$' | awk -v t=$THRESHOLD '$1 < t')
    for SNAPSHOT in $TO_BE_CLEARED
    do 
        nodetool clearsnapshot -t $SNAPSHOT
    done
}

# Function to take node-specific snapshot
take_node_snapshot() {
    log "Taking snapshot on node ${LOCAL_NODE}"
    
    cleanup_old_snapshots
    
    # Take new snapshot
    if nodetool snapshot -t "$BACKUP_NAME"; then
        log "Snapshot created successfully on ${LOCAL_NODE}"
    else
        log "ERROR: Failed to create snapshot on ${LOCAL_NODE}"
        exit 1
    fi
}

# Function to collect snapshot files
collect_snapshot_files() {
    local node_backup_dir="${BACKUP_BASE_DIR}/${BACKUP_NAME}/${LOCAL_NODE}"
    mkdir -p "$node_backup_dir"
    
    log "Collecting snapshot files on ${LOCAL_NODE}"
    
    # Find and copy snapshot files
    find /var/lib/cassandra/data -type d -name "$BACKUP_NAME" | while read snapshot_dir; do
        # Extract keyspace and table names from path
        local keyspace=$(echo "$snapshot_dir" | awk -F'/' '{print $(NF-3)}')
        local table=$(echo "$snapshot_dir" | awk -F'/' '{print $(NF-2)}')
        
        # Create destination directory structure
        local dest_dir="$node_backup_dir/$keyspace/$table"
        mkdir -p "$dest_dir"
        
        # Copy files with progress indication
        log "Copying $keyspace/$table"
        cp -r "$snapshot_dir"/* "$dest_dir/"
    done
}

# Function to compress backup files
compress_backup() {
    local node_backup_dir="${BACKUP_BASE_DIR}/${BACKUP_NAME}/${LOCAL_NODE}"
    log "Compressing backup files on ${LOCAL_NODE}"
    
    cd "${BACKUP_BASE_DIR}"
    tar -czf "${BACKUP_NAME}_${LOCAL_NODE}.tar.gz" "${BACKUP_NAME}/${LOCAL_NODE}"
    
    if [ $? -eq 0 ]; then
        log "Backup compressed successfully"
        # Clean up uncompressed files
        rm -rf "${BACKUP_NAME}/${LOCAL_NODE}"
    else
        log "ERROR: Compression failed"
        exit 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups"
    
    # Remove old snapshots from Cassandra
    cleanup_old_snapshots
    
    # Remove old backup files
    find "${BACKUP_BASE_DIR}" -maxdepth 1 -type f -name "cluster_backup_*_${LOCAL_NODE}.tar.gz" -mtime +${RETENTION_DAYS} -exec rm -f {} \;
    
    log "Cleanup completed"
}

# Function to verify backup
verify_backup() {
    local backup_file="${BACKUP_BASE_DIR}/${BACKUP_NAME}_${LOCAL_NODE}.tar.gz"
    
    # Check if backup file exists and is not empty
    if [ ! -f "$backup_file" ]; then
        log "ERROR: Backup file not found: $backup_file"
        return 1
    fi
    
    if [ ! -s "$backup_file" ]; then
        log "ERROR: Backup file is empty: $backup_file"
        return 1
    fi
    
    # Try to list contents of backup
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        log "ERROR: Backup file is corrupted: $backup_file"
        return 1
    fi
    
    log "Backup verification completed successfully"
    return 0
}

# Main backup process
main() {
    log "Starting Cassandra cluster backup process on ${LOCAL_NODE}"
    
    # Execute backup sequence
    check_cluster_health
    backup_schema
    take_node_snapshot
    collect_snapshot_files
    compress_backup
    verify_backup
    cleanup_old_backups
    
    log "Backup process completed successfully on ${LOCAL_NODE}"
}

# Execute main function with error handling
main "$@" || {
    log "ERROR: Backup failed on ${LOCAL_NODE}"
    exit 1
}