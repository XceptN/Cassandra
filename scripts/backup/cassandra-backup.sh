#!/bin/bash

# Configuration variables
CASSANDRA_DATA_DIR="/var/lib/cassandra/data"
BACKUP_DIR="/backup/cassandra"
SNAPSHOT_NAME="backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/cassandra/backup.log"
RETENTION_DAYS=7

# Ensure backup directory exists
mkdir -p $BACKUP_DIR

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Check if Cassandra is running
if ! nodetool status >/dev/null 2>&1; then
    log "ERROR: Cassandra is not running. Exiting."
    exit 1
fi

# Function to take snapshot
take_snapshot() {
    log "Creating new snapshot: $SNAPSHOT_NAME"
    if nodetool snapshot -t $SNAPSHOT_NAME; then
        log "Snapshot created successfully"
    else
        log "ERROR: Failed to create snapshot"
        exit 1
    fi
}

# Function to backup schema
backup_schema() {
    log "Backing up schema"
    cqlsh -e "DESC SCHEMA" > "$BACKUP_DIR/schema_$SNAPSHOT_NAME.cql" 2>>$LOG_FILE
    if [ $? -eq 0 ]; then
        log "Schema backup completed"
    else
        log "ERROR: Schema backup failed"
        exit 1
    fi
}

# Function to copy snapshot files
copy_snapshot_files() {
    log "Copying snapshot files to backup directory"
    
    find $CASSANDRA_DATA_DIR -type d -name "$SNAPSHOT_NAME" | while read snapshot_dir; do
        keyspace=$(echo $snapshot_dir | awk -F'/' '{print $(NF-3)}')
        table=$(echo $snapshot_dir | awk -F'/' '{print $(NF-2)}')
        
        # Create destination directory
        dest_dir="$BACKUP_DIR/$SNAPSHOT_NAME/$keyspace/$table"
        mkdir -p "$dest_dir"
        
        # Copy files
        cp -r "$snapshot_dir"/* "$dest_dir/"
    done
    
    log "Snapshot files copied successfully"
}

# Function to clean up old snapshots
cleanup_old_snapshots() {
    log "Cleaning up old snapshots"
    
    # Remove old Cassandra snapshots
    nodetool clearsnapshot
    
    # Remove old backup directories
    find $BACKUP_DIR -maxdepth 1 -type d -mtime +$RETENTION_DAYS -name "backup_*" | while read dir; do
        log "Removing old backup: $dir"
        rm -rf "$dir"
    done
}

# Function to compress backup
compress_backup() {
    log "Compressing backup"
    cd $BACKUP_DIR
    tar -czf "${SNAPSHOT_NAME}.tar.gz" $SNAPSHOT_NAME/
    if [ $? -eq 0 ]; then
        log "Backup compressed successfully"
        rm -rf $SNAPSHOT_NAME/
    else
        log "ERROR: Compression failed"
        exit 1
    fi
}

# Main backup process
log "Starting Cassandra backup process"

# Take snapshot
take_snapshot

# Backup schema
backup_schema

# Copy snapshot files
copy_snapshot_files

# Compress backup
compress_backup

# Cleanup old snapshots and backups
cleanup_old_snapshots

log "Backup process completed successfully"