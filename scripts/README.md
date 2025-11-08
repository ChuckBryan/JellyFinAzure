# Jellyfin Azure - Management Scripts

This folder previously contained backup management scripts for the JellyRoller backup system. 

Since the setup has been migrated to use SQL Server for data storage, the backup scripts have been removed as they are no longer needed.

## Current Setup

The Jellyfin deployment now uses:
- **SQL Server Database** for all data storage (metadata, user data, configurations)
- **Azure File Share** for media files only
- **No backup automation** - SQL Server provides its own backup and recovery mechanisms

## Managing Your Setup

- **SQL Database**: Use Azure SQL Database backup features through Azure Portal
- **Media Files**: Managed through Azure Storage Explorer
- **Configuration**: Stored in SQL Server database, backed up automatically by Azure SQL

For any database operations, use the Azure Portal SQL Database management tools or Azure CLI commands specific to SQL databases.
