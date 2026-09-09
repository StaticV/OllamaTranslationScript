param(
    [Parameter(Mandatory=$false)]
    [string]$i = ".\locality_files",

    [Parameter(Mandatory=$false)]
    [string]$o = ".\ukrainian_locality_files",

    [Parameter(Mandatory=$false)]
    [string]$m = "qwen2.5:32b",

    [Parameter(Mandatory=$false)]
    [string]$u = "http://localhost:11434/api/chat",

    [Parameter(Mandatory=$false)]
    [string]$l = "Ukrainian"
)

# Build system prompt dynamically based on the target language parameter
$systemPrompt = @"
You are a precise localization and translation assistant. Your task is to translate all human-readable string values in the provided JSON from English to $l.
CRITICAL RULES:
1. Keep ALL JSON keys, IDs, and structure 100% identical. Only translate the string values.
2. Use correct regional, administrative, and geographic terminology for $l.
3. Return ONLY valid JSON, with no markdown formatting code blocks (like ```json) and no conversational filler.
"@

# Check if input directory exists
if (-not (Test-Path $i)) {
    Write-Host "Error: Input directory '$i' does not exist." -ForegroundColor Red
    exit
}

# Get all JSON files recursively
$jsonFiles = Get-ChildItem -Path $i -Filter "*.json" -Recurse
$totalFiles = $jsonFiles.Count

if ($totalFiles -eq 0) {
    Write-Host "No JSON files found in $i" -ForegroundColor Yellow
    exit
}

Write-Host "Found $totalFiles JSON files to process." -ForegroundColor Cyan
Write-Host "Configuration -> Model: $m | Target Language: $l | Input: $i | Output: $o" -ForegroundColor DarkCyan
Write-Host "--------------------------------------------------------"

$currentIndex = 0
foreach ($file in $jsonFiles) {
    $currentIndex++
    
    # Calculate relative path to mirror subdirectories
    $relativePath = $file.FullName.Substring((Resolve-Path $i).Path.Length + 1)
    $outputPath = Join-Path $o $relativePath
    $outputParent = Split-Path $outputPath -Parent

    # Create output subdirectory if it doesn't exist
    if (-not (Test-Path $outputParent)) {
        New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
    }

    Write-Host "[$currentIndex/$totalFiles] Processing: $relativePath..." -NoNewline

    try {
        # Read JSON file content safely with UTF-8
        $jsonContent = Get-Content -Path $file.FullName -Raw -Encoding utf8

        # Construct payload for Ollama API
        $body = @{
            model = $m
            messages = @(
                @{ role = "system"; content = $systemPrompt },
                @{ role = "user"; content = $jsonContent }
            )
            stream = $false
            options = @{
                temperature = 0.1
            }
        } | ConvertTo-Json -Depth 10

        # Send request to local Ollama instance
        $response = Invoke-RestMethod -Uri $u -Method Post -Body $body -ContentType "application/json"
        $rawContent = $response.message.content.Trim()

        # Clean markdown ticks if the model included them (using safe .Split methods)
        if ($rawContent.StartsWith("```")) {
            $lines = $rawContent.Split(@("`r`n", "`n"), [System.StringSplitOptions]::None)
            if ($lines[0].Trim().StartsWith("```")) { $lines = $lines[1..($lines.Length - 1)] }
            if ($lines[$lines.Length - 1].Trim().StartsWith("```")) { $lines = $lines[0..($lines.Length - 2)] }
            $rawContent = [string]::Join([Environment]::NewLine, $lines).Trim()
        }

        # Validate that the response is valid JSON
        $null = $rawContent | ConvertFrom-Json

        # Save to output file
        [System.IO.File]::WriteAllText($outputPath, $rawContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host " SUCCESS" -ForegroundColor Green

    } catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor DarkRed
        
        # Save raw output to an error file for inspection
        if ($response -and $response.message -and $response.message.content) {
            $errorPath = [System.IO.Path]::ChangeExtension($outputPath, ".error.txt")
            [System.IO.File]::WriteAllText($errorPath, $response.message.content, [System.Text.UTF8Encoding]::new($false))
        }
    }
}

Write-Host "`nBatch translation complete!" -ForegroundColor Cyan
