
# Read config paths file
$pathsFile = ".\paths.conf"
$pathsTable = Get-Content -Path $pathsFile | ForEach-Object {
    $key, $value = $_ -split '='
    @{ $key.Trim() = (Resolve-Path -Path $value.Trim()).Path }
} | Group-Object -Property Keys -AsHashTable
# Retrieve values from the config paths hashtable
$eliteInsightsDir = "..\GW2-Elite-Insights-Parser"

# Specific script paths
$topStatsParserDir = "..\arcdps_top_stats_parser"
$customConfigPath = ".\custom-config"
$logsPath = ".\data\logs"
$jsonPath = ".\data\json"

# Update latest repositories if Git is installed
if (Get-Command git -ErrorAction SilentlyContinue) {
    # Update Git submodules
    git submodule update --remote
} else {
    Write-Output "Git not installed, skipping repositories update."
}

# Copy current .zevtc from Gw2 ArcDps folder
$arcDpslogsDir = $pathsTable["ARC_DPS_LOGS_DIR"]
# ... WIP

# Copy custom config into respective repositories
# 1. EI_detailed_json_combat_replay.conf to ELITE_INSIGHTS_DIR
# 2. Guild_Data.py to TOP_STATS_PARSER_DIR

# Convert .zevtc to .json files, using GW2-Elite-Insights-Parser
foreach ($file in Get-ChildItem -Path "$logsPath\*.zevtc") {
    & "$eliteInsightsDir\GuildWars2EliteInsights.exe" -c "$customConfigPath\EI_detailed_json_combat_replay.conf" "$file.FullName"
}

# Generate .html file from .json, using arcdps_top_stats_parser
python "$topStatsParserDir\TW5_parse_top_stats_detailed.py" $jsonPath



