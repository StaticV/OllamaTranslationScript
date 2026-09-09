param(
    [Parameter(Mandatory=$false)]
    [Alias("i")]
    [string]$InputFolder = ".\json_files",

    [Parameter(Mandatory=$false)]
    [Alias("o")]
    [string]$OutputFolder = ".\ukrainian_json",

    [Parameter(Mandatory=$false)]
    [Alias("l")]
    [string]$TargetLanguage = "Ukrainian",

    [Parameter(Mandatory=$false)]
    [Alias("m")]
    [string]$ModelName = "llama3"
)

# Ensure output folder exists
if (!(Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
}

# Function to recursively translate text
function Translate-JsonData {
    param ($data)

    if ($null -eq $data) {
        return $null
    }

    # If it's a string, translate it
    if ($data -is [string]) {
        if ([string]::IsNullOrWhiteSpace($data)) { return $data }
        
        Write-Host "Translating: $($data.Substring(0, [Math]::Min(30, $data.Length)))..."

        $prompt = "Translate the following English text into $TargetLanguage. Return ONLY the translated text without any extra explanations, notes, or quotation marks:`n`n$data"
        
        $body = @{
            model  = $ModelName
            prompt = $prompt
            stream = $false
        } | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json"
            $translated = $response.response.Trim()
            if ([string]::IsNullOrEmpty($translated)) { return $data }
            return $translated
        } catch {
            Write-Warning "Translation error: $_"
            return $data
        }
    }
    # If it's an array, loop through items
    elseif ($data -is [System.Collections.IEnumerable] -and $data -isnot [string]) {
        $translatedList = foreach ($item in $data) {
            Translate-JsonData -data $item
        }
        return @($translatedList)
    }
    # If it's an object/dictionary, loop through properties
    elseif ($data -is [PSCustomObject] -or $data -is [System.Collections.IDictionary]) {
        foreach ($key in $data.PSObject.Properties.Name) {
            $data.$key = Translate-JsonData -data $data.$key
        }
        return $data
    }
    
    return $data
}

# Process all JSON files in the input folder
Get-ChildItem -Path $InputFolder -Filter "*.json" | ForEach-Object {
    $filePath = $_.FullName
    $outputPath = Join-Path $OutputFolder $_.Name

    Write-Host "`nProcessing file: $($_.Name)" -ForegroundColor Cyan

    try {
        # Read JSON file (PowerShell 7 handles this natively)
        $jsonContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json

        # Translate data
        $translatedContent = Translate-JsonData -data $jsonContent

        # Save back to output folder as JSON
        $translatedContent | ConvertTo-Json -Depth 100 | Set-Content -Path $outputPath -Encoding utf8

        Write-Host "Saved to: $outputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to process $($_.Name): $_"
    }
}

Write-Host "`nAll translations complete!" -ForegroundColor Cyan
