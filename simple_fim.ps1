#
# Monitor a web root (or any directory) for changes.
#
param (
    [Parameter(Mandatory=$true)]
    [string]$Mode,
    [Parameter(Mandatory=$true)]
    [string]$WebRoot,
    [Parameter(Mandatory=$true)]
    [string]$JsonDbPath,
    [Parameter(Mandatory=$true)]
    [string]$BackupDir
)

<# if ((Get-ExecutionPolicy) -ne 'Byass') {
    Start-Process -Verb RunAs powershell -ArgumentList "-ExecutionPolicy Bypass -File $($MyInvocation.MyCommand.Path)"
    exit
} #>

function Get-FileData {
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupDir
    )

    $results = $()

    Get-ChildItem -Path $Path -Recurse -File | ForEach-Object {
        $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
        $results += [PSCustomObject]@{
            'Path'              = $_.FullName;
            'SHA256'            = $hash.Hash;
            'Created'           = $_.CreationTime;
            'Modified'          = $_.LastWriteTime;
            'SizeInBytes'       = $_.Length;
        }
    }

    return $results;
}


function Save-FileData {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$Data
    )

    $Data | ConvertTo-Json -Depth 10 | Out-File $Path
}


function Convert-FileData {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $file_data_list = New-Object 'System.Collections.Generic.List[PSObject]'

    try {
        $json_data = Get-Content -Path | ConvertFrom-Json
    } catch {
        Write-Error "The provided path does not exist or is not accessible ($Path)"
        exit 1
    }

    foreach ($file in $json_data) {
        $obj = New-Object PSObject -Property @{
            'Path'          = $file.Path;
            'SHA256'        = $file.SHA256;
            'Created'       = $file.Created;
            'Modified'      = $file.Modified;
            'SizeInBytes'   = $file.SizeInBytes;
        }
        $file_data_list.Add($obj)
    }

    return $file_data_list
}


function Copy-ModifiedFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [Parameter(Mandatory=$true)]
        [string]$DestinationDir
    )

    # Get the file extension and base name of file.
    $file_ext = [System.IO.Path]::GetExtension($FilePath)
    $base_name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    # Get timestamp
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $sha256 = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    # "." is included with GetExtension.
    $new_file_name = "${base_name}__${timestamp}_${sha256}${file_ext}"

    # Form the destination path.
    $dest_path = Join-Path -Path $DestinationDir -ChildPath $new_file_name

    # Copy file over.
    Copy-Item -Path $FilePath -Destination $dest_path

    return $dest_path
}


function Compare-FileData {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CurrentData,
        [Parameter(Mandatory=$true)]
        [string]$OldData
    )

    $changes = @()
    $changes += "`n"

    # Ensure backup directory exists.
    try {
        if (-not (Test-Path $BackupDir)) {
            New-Item -ItemType Directory -Path $BackupDir -Force
        }
    } catch {
        Write-Error "Failed to create the backup directory ($BackupDir).  Erorr: $_"
        exit 1
    }

    $CurrentData | ForEach-Object {
        $current = $_
        $old = $OldData | Where-Object { $_.Path -eq $current.Path }

        if ($old) {
            if ($old.SHA256 -ne $current.SHA256) {
                $changes += "Modified file:  $($current.Path)`n"
                $changes += "Original -> SHA256:  $($old.SHA256), Created:  $($old.Created), Modified:  $($old.Modified), SizeInBytes:  $($old.SizeInBytes)`n"
                $changes += "New      -> SHA256:  $($current.SHA256), Created:  $($current.Created), Modified:  $($current.Modified), SizeInBytes:  $($current.SizeInBytes)`n"

                $backup_file_path = Copy-ModifiedFile -FilePath $current.Path $DestinationDir $BackupDir
                $changes += "Backup of modified file saved to:  $backup_file_path`n"
            }

            $changes += "Current: $($current.Path)`n"
        } else {
            $changes += "New File:  $($current.Path)`n"
            $changes += "SHA256:  $($current.SHA256), Created:  $($current.Created), Modified:  $($current.Modified), SizeInBytes:  $($current.SizeInBytes)`n"
        }
    }

    $OldData | ForEach-Object {
        $old = $_
        $current = $CurrentData | Where-Object { $_.Path.Trim() -eq $old.Path.Trim() }
        if (-not $current) {
            $changes += "Deleted File:  $($old.Path)`n"
            $changes += "SHA256:  $($old.SHA256), Created:  $($old.Created), Modified:  $($old.Modified), SizeInBytes:  $($old.SizeInBytes)`n"
        }
    }

    return @{
        "Changes" = $changes;
    }
}


if ($Mode -eq "modify") {
    $data = Get-FileData -Path $WebRoot
    SaveFileData -Path $JsonDbPath - Data $data
} elseif ($Mode -eq "monitor") {
    $old_data = Convert-FileData -Path $JsonDbPath
    $current_data = Get-FileData -Path $WebRoot
    $changes = Compare-FileData -CurrentData $current_data -OldData $old_data

    $changes | ForEach-Object {
        $_.GetEnumerator() | ForEach-Object {
            Write-Output "$($_.Key):  $($_.Value)"
        }
    }
} else {
    <#
    You have "modify" mode for when you wish to create a new snapshot of your current directory structure.
    You have "monitor" for when you want to compare the current directory structure to a known-good state.
        If alterations are found, copies are made and logged in your backup directory for each run,
        including the SHA256 and timestamp of the offending file(s).
    #>
    Write-Host "Invalid Usage.  Please use the following:"
    Write-Host ".\$($MyInvocation.MyCommand.Name) -Mode ""modify"" -WebRoot ""C:\path\to\web\root"" -JsonDbPath ""C:\path\to\output.json"" -BackupDir ""backup"""
    Write-Host ".\$($MyInvocation.MyCommand.Name) -Mode ""monitor"" -WebRoot ""C:\path\to\web\root"" -JsonDbPath ""C:\path\to\output.json"" -BackupDir ""backup"""
}
