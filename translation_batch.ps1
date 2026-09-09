param(
    [Parameter(Mandatory=$false)]
    [Alias("i")]
    [string]$InputFolder = ".\json_files",

    [Parameter(Mandatory=$false)]
    [Alias("o")]
    [string]$OutputFolder = ".\ukrainian_json",

    [Parameter(Mandatory=$false)]
    [Alias("m")]
    [string]$ModelName = "translategemma",

    [Parameter(Mandatory=$false)]
    [Alias("sl")]
    [string]$SourceLang = "English",

    [Parameter(Mandatory=$false)]
    [Alias("sc")]
    [string]$SourceCode = "en",

    [Parameter(Mandatory=$false)]
    [Alias("tl")]
    [string]$TargetLang = "Ukrainian",

    [Parameter(Mandatory=$false)]
    [Alias("tc")]
    [string]$TargetCode = "uk"
)

# Normalize paths to avoid slash mismatch issues
$InputFolder = (Resolve-Path $InputFolder).Path
$OutputFolder = [System.IO.Path]::GetFullPath($OutputFolder)

function Translate-JsonData {
    param ($data)

    if ($null -eq $data) {
        return $null
    }

    if ($data -is [PSCustomObject] -or $data -is [System.Collections.IDictionary]) {
        foreach ($key in $data.PSObject.Properties.Name) {
            $val = $data.$key

            if ($val -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $preview = if ($val.Length -gt 30) { $val.Substring(0, 30) + "..." } else { $val }
                    Write-Host "Translating [$key]: '$preview'" -NoNewline

                    $systemPrompt = "You are a professional ${SourceLang} (${SourceCode}) to ${TargetLang} (${TargetCode}) translator. Your goal is to accurately convey the meaning and nuances of the original ${SourceLang} text while adhering to ${TargetLang} grammar, vocabulary, and cultural sensitivities.`nProduce only the ${TargetLang} translation, without any additional explanations or commentary. Please translate the following ${SourceLang} text into ${TargetLang}:"

                    $body = @{
                        model  = $ModelName
                        messages = @(
                            @{
                                role = "system"
                                content = $systemPrompt
                            },
                            @{
                                role = "user"
                                content = $val
                            }
                        )
                        stream = $false
                        options = @{
                            temperature = 0.0
                        }
                    } | ConvertTo-Json -Depth 10

                    try {
                        $response = Invoke-RestMethod -Uri "http://localhost:11434/api/chat" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30
                        $translated = $response.message.content.Trim()
                        
                        if ($translated -match "(?i)(Note:|Explanation:|->)\s*(.*)") {
                            $translated = $matches[2].Trim("`"' ")
                        }

                        if (-not [string]::IsNullOrEmpty($translated)) {
                            $data.$key = $translated
                            Write-Host " -> Done" -ForegroundColor Green
                        } else {
                            Write-Host " -> Empty response, kept original" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host " -> TIMED OUT / ERROR" -ForegroundColor Red
                        # Using Write-Error so it routes to PowerShell's error stream for redirection
                        Write-Error "Failed to translate key '$key' with value '$preview': $_"
                    }
                }
            }
            elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $data.$key = Translate-JsonData -data $val
            }
            elseif ($val -is [PSCustomObject] -or $val -is [System.Collections.IDictionary]) {
                $data.$key = Translate-JsonData -data $val
            }
        }
        return $data
    }
    elseif ($data -is [System.Collections.IEnumerable] -and $data -isnot [string]) {
        $translatedList = foreach ($item in $data) {
            Translate-JsonData -data $item
        }
        return @($translatedList)
    }
    
    return $data
}

# Process all JSON files recursively in the input folder and subdirectories
Get-ChildItem -Path $InputFolder -Filter "*.json" -Recurse | ForEach-Object {
    $filePath = $_.FullName
    
    $relativePath = [System.IO.Path]::GetRelativePath($InputFolder, $filePath)
    $outputPath = Join-Path $OutputFolder $relativePath
    $outputDir = [System.IO.Path]::GetDirectoryName($outputPath)

    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    }

    Write-Host "`nProcessing file: $relativePath" -ForegroundColor Cyan

    try {
        $jsonContent = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        $translatedContent = Translate-JsonData -data $jsonContent
        $translatedContent | ConvertTo-Json -Depth 100 | Set-Content -Path $outputPath -Encoding utf8

        Write-Host "Successfully saved: $outputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to process file $relativePath : $_"
    }
}

Write-Host "`nAll batch processing complete!" -ForegroundColor Cyan
