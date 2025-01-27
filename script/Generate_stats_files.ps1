# Read config file
$configFile = ".\edit_me.conf"
$configTable = @{}
Get-Content -Path $configFile | ForEach-Object {
  if ($_ -match '=') {
    $key, $value = $_ -split '='
    $configTable[$key.Trim()] = $value.Trim('"')
  }
}

# Retrieve values from the config hashtable
if (-not $configTable.ContainsKey("ARC_DPS_LOGS_DIR")) {
  Write-Error "ARC_DPS_LOGS_DIR not found. Please check your edit_me.conf file."
  Read-Host
  exit 1
}
$arcDpslogsDir = $configTable["ARC_DPS_LOGS_DIR"]
$resolvedPath = Resolve-Path -Path $arcDpslogsDir -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
  Write-Error "Cannot resolve the ARC_DPS_LOGS_DIR path. Please provide in edit_me.conf file a correct path (e.g. `C:\Program Files (x86)\Guild Wars 2\addons\arcdps\arcdps.cbtlogs\WvW (1)\Player`)."
  Read-Host
  exit 1
}

# Retrieve date from the config hashtable
if ($configTable.ContainsKey("EXTRACT_DATE")) {
  $dateFilter = $configTable["EXTRACT_DATE"]
  if ($dateFilter -eq "") {
    $dateFilter = (Get-Date).ToString("yyyyMMdd")
  }
  elseif ($dateFilter -notmatch '^\d{8}$') {
    Write-Error "Invalid EXTRACT_DATE format. Please use YYYYMMDD format."
    Read-Host
    exit 1
  }
}
else {
  $dateFilter = (Get-Date).ToString("yyyyMMdd")
}

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

# Initialize and update Git submodules
# Update latest repositories if Git is installed
if (Get-Command git -ErrorAction SilentlyContinue) {
  # Initialize your local configuration file
  git submodule init
  # Fetch all the data from sub-repositories
  git submodule update
}
else {
  Write-Error "Git not installed, can't initialize and fetch needed repositories. Please install it from https://git-scm.com/downloads."
  Read-Host
  exit 1
}

# Prepare the environment for the Python script
Write-Output "##############################################################################"
Write-Output "### 1. Prepare the environment ###############################################"
Write-Output "###### Configuration #########################################################"
Write-Output "###### In-game logs path:     $arcDpslogsDir"
Write-Output "###### Extract date:          $dateFilter"
## Check if python3 is installed to continue, and install required Python packages
Write-Output "######## Install required Python packages ####################################"
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Error "Python3 is not installed. Please install it from https://www.python.org/downloads/."
  Read-Host
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
      Read-Host
      exit 1
    }
  }
  else {
    Write-Output "Package already installed: $_"
  }
}

## Fixing `ModuleNotFoundError: No module named 'cgi'` error in TW5_parse_top_stats_tools.py file
Write-Output "######## Fixing TW5_parse_top_stats_tools.py file ############################"
$filePath = "..\arcdps_top_stats_parser\TW5_parse_top_stats_tools.py"
(Get-Content -Path $filePath) | ForEach-Object {
  if ($_ -match "# from cgi import test") {
    $_
  }
  elseif ($_ -match "from cgi import test") {
    "# $_"
  }
  else {
    $_
  }
} | Set-Content -Path $filePath

## Remove old data files
Write-Output "######## Removing old data files #############################################"
if ((Test-Path -Path $dataPath)) {
  Remove-Item -Path $dataPath -Recurse -Force
}

## Copy specific .zevtc files from arcdps.cbtlogs folder
Write-Output "######## Copying specific .zevtc files from ArcDps folder ####################"
if (-not (Test-Path -Path $logsPath)) {
  New-Item -ItemType Directory -Path $logsPath > $null
}
Copy-Item -Path "$arcDpslogsDir\$dateFilter*.zevtc" -Destination $logsPath

# Copy custom config into respective repositories
# - Guild_Data.py to arcdps_top_stats_parser
# if (-not (Test-Path -Path $topStatsParserDir)) {
#     New-Item -ItemType Directory -Path $topStatsParserDir
# }
# Copy-Item -Path "$customConfigPath\Guild_Data.py" -Destination $topStatsParserDir  -Force

Write-Output "##############################################################################"
Write-Output "### 2. Parse files & generate stats ##########################################"
# Convert .zevtc to .json files, using GW2-Elite-Insights-Parser
Write-Output "######## Converting .zevtc to .json, using GW2-Elite-Insights-Parser #########"
## Check if there are .zevtc files to convert
$zevtcFiles = Get-ChildItem -Path "$logsPath\*.zevtc"
if ($zevtcFiles.Count -eq 0) {
  Write-Output "No .zevtc files found to process."
  Read-Host
  exit 1
}
if (-not (Test-Path -Path $jsonPath)) {
  New-Item -ItemType Directory -Path $jsonPath > $null
}
foreach ($file in Get-ChildItem -Path "$logsPath\*.zevtc") {
  # TODO: add verbose option
  & "$eliteInsightsDir\GuildWars2EliteInsights-CLI.exe" -c "$customConfigPath\EI_detailed_json_combat_replay_custom.conf" "$file" > $null
}
Get-ChildItem -Path "$logsPath\*.json" | ForEach-Object {
  Move-Item -Path $_.FullName -Destination $jsonPath -Force
}

# Generate .tid file from .json, using arcdps_top_stats_parser
Write-Output "######## Generating .tid file from .json, using arcdps_top_stats_parser ######"
python "$topStatsParserDir\TW5_parse_top_stats_detailed.py" $jsonPath > $null
if (-not (Test-Path -Path $tidPath)) {
  New-Item -ItemType Directory -Path $tidPath > $null
}
Get-ChildItem -Path "$jsonPath\*.tid" | ForEach-Object {
  Copy-Item -Path $_.FullName -Destination $tidPath -Force
}

Write-Output "##############################################################################"
Write-Output "### 3. Upload .tid to show in web page #######################################"
Write-Output "##############################################################################"
Write-Output ""
Write-Output "==> Please import .tid files to your hosted TW5_Top_Stat_Parse.html, then press red top-right Save button to get the .html file. <=="
Write-Output ""

# Success! \o/
Write-Output "Script execution completed. Press Enter to exit."
Read-Host
exit 0