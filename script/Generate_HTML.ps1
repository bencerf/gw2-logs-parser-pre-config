# Read config file
$configFile = ".\edit_me.conf"
$configTable = @{}
Get-Content -Path $configFile | ForEach-Object {
  if ($_ -match '=') {
    $key, $value = $_ -split '='
    $resolvedPath = Resolve-Path -Path $value.Trim('"') -ErrorAction SilentlyContinue
    if ($resolvedPath) {
      $configTable[$key.Trim()] = $resolvedPath.Path
    }
    else {
      Write-Error "Config not found: $value"
    }
  }
}

# Retrieve values from the config hashtable
if (-not $configTable.ContainsKey("ARC_DPS_LOGS_DIR")) {
  Write-Error "ARC_DPS_LOGS_DIR not found. Check your edit_me.conf file."
  exit 1
}
$arcDpslogsDir = $configTable["ARC_DPS_LOGS_DIR"]
# TODO: Add date or not

# Specific script paths
# TODO: fetch latest, instead static
# $eliteInsightsDir = "..\GW2-Elite-Insights-Parser"
$eliteInsightsDir = "..\GW2EICLI"
$topStatsParserDir = "..\arcdps_top_stats_parser"
$customConfigPath = ".\custom-config"
$dataPath = ".\data"
$logsPath = ".\data\logs"
$jsonPath = ".\data\json"
$tidPath = ".\data\tid"
$htmlPath = ".\data\html"

# Initialize and update Git submodules
# Update latest repositories if Git is installed
if (Get-Command git -ErrorAction SilentlyContinue) {
  # Initialize your local configuration file
  git submodule init
  # Fetch all the data from sub-repositories
  git submodule update
}
else {
  Write-Error "Git not installed, can't initialize and fetch needed repositories."
  exit 1
}

# Prepare the environment for the Python script
Write-Output "##############################################################################"
Write-Output "### 1. Prepare the environment ###############################################"
Write-Output "##############################################################################"
## Check if python3 is installed to continue, and install required Python packages
Write-Output "###### Install required Python packages ######################################"
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Error "Python3 is not installed. Please install it from https://www.python.org/downloads/."
  exit 1
}
$pipPackages = @("xlrd", "xlutils", "xlwt", "jsons", "requests", "xlsxwriter")
function Test-PythonPackage {
  param (
    [string]$PackageName
  )
  $result = python -c "import $PackageName" 2>&1
  return ($result -eq "")
}
$pipPackages | ForEach-Object {
  if ((Test-PythonPackage -PackageName $_)) {
    Write-Output "Installing package: $_"
    python -m pip install $_ -q
    if (-not $?) {
      Write-Error "Failed to install package: $_. Please install it manually."
      exit 1
    }
  }
  else {
    Write-Output "Package already installed: $_"
  }
}
## Remove old data files
Write-Output "###### Removing old data files ###"
if ((Test-Path -Path $dataPath)) {
  Remove-Item -Path $dataPath -Recurse -Force
}

## Copy specific .zevtc files from arcdps.cbtlogs folder
Write-Output "###### Copying specific .zevtc files from ArcDps folder ###"
if (-not (Test-Path -Path $logsPath)) {
  New-Item -ItemType Directory -Path $logsPath > $null
}
Copy-Item -Path "$arcDpslogsDir\*.zevtc" -Destination $logsPath

# Copy custom config into respective repositories
# - Guild_Data.py to arcdps_top_stats_parser
# if (-not (Test-Path -Path $topStatsParserDir)) {
#     New-Item -ItemType Directory -Path $topStatsParserDir
# }
# Copy-Item -Path "$customConfigPath\Guild_Data.py" -Destination $topStatsParserDir  -Force

Write-Output "##############################################################################"
Write-Output "### 2. Parse files & generate stats ##########################################"
Write-Output "##############################################################################"
# Convert .zevtc to .json files, using GW2-Elite-Insights-Parser
Write-Output "###### Converting .zevtc to .json, using GW2-Elite-Insights-Parser ###########"
## Check if there are .zevtc files to convert
$zevtcFiles = Get-ChildItem -Path "$logsPath\*.zevtc"
if ($zevtcFiles.Count -eq 0) {
  Write-Output "No .zevtc files found to process."
  exit 1
}
if (-not (Test-Path -Path $jsonPath)) {
  New-Item -ItemType Directory -Path $jsonPath > $null
}
foreach ($file in Get-ChildItem -Path "$logsPath\*.zevtc") {
  # Add verbose option
  & "$eliteInsightsDir\GuildWars2EliteInsights-CLI.exe" -c "$customConfigPath\EI_detailed_json_combat_replay_custom.conf" "$file" > $null
}
Get-ChildItem -Path "$logsPath\*.json" | ForEach-Object {
  Copy-Item -Path $_.FullName -Destination $jsonPath -Force
}

# Generate .html file from .json, using arcdps_top_stats_parser
Write-Output "###### Generating .html file from .json, using arcdps_top_stats_parser #######"

## Generate .tid files from .json
python "$topStatsParserDir\TW5_parse_top_stats_detailed.py" $jsonPath > $null
if (-not (Test-Path -Path $tidPath)) {
  New-Item -ItemType Directory -Path $tidPath > $null
}
Get-ChildItem -Path "$jsonPath\*.tid" | ForEach-Object {
  Copy-Item -Path $_.FullName -Destination $tidPath -Force
}
## Generate .html files from .tid
if (-not (Test-Path -Path $htmlPath)) {
  New-Item -ItemType Directory -Path $htmlPath > $null
}

# Success! \o/
exit 0