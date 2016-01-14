$ErrorActionPreference="Stop"

# Global variables.
$arch = "$env:PROCESSOR_ARCHITECTURE".ToLower()
$agent = "neptune-agent.exe"
$config = "neptune-agent.json"
$stable_agent_url = "https://raw.githubusercontent.com/neptuneio/neptune-agent/prod/downloads/neptune-agent-windows-$arch.zip"
$api_key = $env:API_KEY
$endpoint = $env:END_POINT
$github_api_key = $env:GITHUB_API_KEY
$log_file_name = "neptune-agent.log"
$assigned_hostname = $env:ASSIGNED_HOSTNAME

# Install the agent in HOME_DIR\neptune
$INSTALL_PATH = Join-Path "$env:userprofile" "neptune"

# Function to download the artifacts
function Download-File {
    param ([string]$url,[string]$file)
    Write-Host "Downloading $url to $file"
    $downloader = new-object System.Net.WebClient
    $downloader.Proxy.Credentials=[System.Net.CredentialCache]::DefaultNetworkCredentials;
    $downloader.DownloadFile($url, $file)
}

# Helper function to unzip the artifacts
function Expand-ZIPFile($file, $destination) {
    $shell = new-object -com shell.application
    $zip = $shell.NameSpace($file)
    Write-Host "Extracting the zip file..."
    foreach($item in $zip.items()) {
        $shell.Namespace($destination).copyhere($item)
    }
}

if (!($api_key)) {
    Write-Error "API_KEY is mandatory. Please set it in the environment."
} else {
    Write-Host "Using the api key: $api_key"
}

if ($endpoint) {
    # Get the artifacts from master if the endpoint is specified.
    $stable_agent_url = "https://raw.githubusercontent.com/neptuneio/neptune-agent/master/downloads/neptune-agent-windows-$arch.zip"
} else {
    $endpoint = "www.neptune.io"
}

if (!($assigned_hostname)) {
    $assigned_hostname = ""
} else {
    Write-Host "Setting the assigned hostname to: $assigned_hostname"
}

Write-Host "Installing Neptune agent for windows ($arch)..."

if ($env:TEMP -eq $null) {
  $env:TEMP = Join-Path "$env:SystemDrive" "temp"
}
$temp = Join-Path "$env:TEMP" "neptune-install"

if (Test-Path $temp) {
    Remove-Item -Force -Recurse -Path $temp
}
New-Item -Force -ItemType directory -Path $temp > $null
$temp_zip_file = Join-Path "$temp" "neptune-agent-windows-$arch.zip"

# Download the artifacts
Download-File "$stable_agent_url" "$temp_zip_file"

# Unzip the artifacts in temp directory
Expand-ZIPFile "$temp_zip_file" "$temp"
if (!$?) {
   Write-Error "Could not unzip the artifacts."
}

# Construct the config file with the passed API_KEY and other values.
$temp_config = Join-Path $temp $config
(Get-Content $temp_config) -replace 'API_KEY_HERE', "$api_key" | Set-Content $temp_config
(Get-Content $temp_config) -replace 'END_POINT_HERE', "$endpoint" | Set-Content $temp_config
(Get-Content $temp_config) -replace 'AGENT_LOG_HERE', "$log_file_name" | Set-Content $temp_config
(Get-Content $temp_config) -replace 'ASSIGNED_HOSTNAME_HERE', "$assigned_hostname" | Set-Content $temp_config
(Get-Content $temp_config) -replace 'GITHUB_KEY_HERE', "$github_api_key" | Set-Content $temp_config

$agent_fullpath = Join-Path $INSTALL_PATH $agent
$config_fullpath = Join-Path $INSTALL_PATH $config
$public_cert_fullpath = Join-Path $INSTALL_PATH "neptuneio.crt"

if (Test-Path $INSTALL_PATH) {
    if (Test-Path $agent_fullpath) {
        # There might be an old instance of agent running already. Try to uninstall it.
        Write-Host "Stopping the old agent.."
        & $agent_fullpath stop

        Write-Host "Uninstalling the old agent service.."
        & $agent_fullpath uninstall
    }

    Remove-Item -Force -Recurse -Path $INSTALL_PATH
}

New-Item -Force -ItemType directory -Path $INSTALL_PATH > $null

# Copy the required files to install directory
Copy-Item -Force "$temp\$agent" $agent_fullpath
Copy-Item -Force "$temp\$config" $config_fullpath
Copy-Item -Force "$temp\neptuneio.crt" $public_cert_fullpath

# Install the agent with install command. This installs agent as NeptuneAgent service.
Write-Host "Installing the agent as service."
& $agent_fullpath install
if (!$?) {
    Write-Error "Could not install the agent as service."
} else {
    Write-Host "Successfully installed the agent as NeptuneAgent service. Now starting the service.."
}

# Start the agent service now.
& $agent_fullpath start
if (!$?) {
    Write-Error "Could not start the agent service."
} else {
    Write-Host "Successfully started the agent.."
}

