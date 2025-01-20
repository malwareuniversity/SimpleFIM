# SimpleFIM
Basic File Integrity Monitoring tool to allow recursively-tracked structural modifications and alerting for unstructured changes to a directory path

Usage:
.\simple_fim.ps1 -Mode "modify" -WebRoot "C:\webroot" -JsonDbPath "path\to\output.json" -BackupDir "path\to\backup"
.\simple_fim.ps1 -Mode "monitor" -WebRoot "C:\webroot" -JsonDbPath "path\to\output.json" -BackupDir "path\to\backup"

MODIFY mode will take a "snapshot" of the current directory structure recursively.  SHA256 is used to identify files.
MONITOR mode will look for any differences between the JSON database (last snapshot from MODIFY) and alert to any changes in file structure (new, modified, and/or deleted files).