# Bootstrap Configuration Directory

This directory contains configuration files used by the bootstrap process.

## Files that will go here:

- `setup.properties` - JellyRoller server setup configuration
- `users.csv` - Bulk user creation file  
- `plugins.txt` - Plugin installation list
- `jellyroller.config` - JellyRoller tool configuration

## Example setup.properties
```ini
MetadataCountryCode=US
PreferredMetadataLanguage=en-US
UICulture=en-US
Name=admin
Password=YourSecurePassword123!
EnableAutomaticPortMapping=false
EnableRemoteAccess=true
```

## Example users.csv
```csv
username,password
user1,password1
user2,password2
testuser,testpass123
```