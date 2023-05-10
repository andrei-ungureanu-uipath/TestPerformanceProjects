param(
    $studioPath = "C:\Dev\beta\Studio\Output\bin\Debug\UiPath.Studio.exe",
    $logsPath = "C:\Users\andrei.ungureanu\AppData\Local\UiPath\Logs",
    $benchmarkProjectsRootPath = "C:\PerformancePipeline\Projects",
    $tempRunFolder = "C:\temp",
    $timeoutPerRunInSeconds = 30,
    $iterationsPerBenchmark = 1
)

Write-Host $studioPath
Write-Host $logsPath
Write-Host $benchmarkProjectsRootPath
Write-Host $tempRunFolder
Write-Host $timeoutPerRunInSeconds
Write-Host $iterationsPerBenchmark

class PerformanceBenchmark {    
    [string]$label
    [string]$duration
    [string]$projectName
    [string]$targetFramework
    [string]$expressionLanguage

    [string] ToString() {
        return "Label: $($this.label), Start Time: $($this.startTime), End Time: $($this.endTime), Duration: $($this.duration)"
    }
}

[string[]]$labels = 
  "OpenProject\s$",
  "LoadAssemblies",
  "Register API",
  "AfterRegistration",
  "Register Metadata",
  "LoadActivitiesAsync",
  "ExecuteStageOneOpen",
  "Register Activities Root",
  "InitializeGlobalVariables",
  "SetActivitiesTypeInformation",
  "InitializeActivitiesFromAssemblies",
  "Entities fix broken installations on project open"
  "Just-in-Time Custom Types fix broken installations on project open"

[PerformanceBenchmark[]]$results = @();

Set-Item -Path env:STUDIO_ENABLE_PERFORMANCE_LOG -Value "test"

$benchmarks = Get-ChildItem -Path $benchmarkProjectsRootPath -Directory

Write-Host "Identified the following benchmarks for running:"
foreach ($benchmark in $benchmarks) {
    Write-Host $benchmark.Name
}

Write-Host ""

function Kill-Studio {
    $processes = Get-Process | Where-Object { $_.ProcessName -like "*UiPath*" }
    $processes | ForEach-Object { Stop-Process $_.Id -Force -ErrorAction SilentlyContinue }

    # Wait for the processes to close
    Start-Sleep -Seconds 1
}

function Run-Benchmark {
    
}

foreach ($benchmark in $benchmarks) {
    Write-Host "Running benchmark: " $benchmark.Name

    $i = 0;
    for ($i = 0; $i -lt $iterationsPerBenchmark; $i++) {    
        Write-Host "Iteration:" $i

        $startTime = Get-Date
        Kill-Studio
        Remove-Item $logsPath\* -Recurse

        $benchmarkFolder = $benchmarkProjectsRootPath + "\" + $benchmark
        $iterationTempFolder = $tempRunFolder + "\" + $benchmark + "_" + $i

        Copy-Item -Path $benchmarkFolder -Destination $iterationTempFolder -Recurse
        $projectJsonPath = $iterationTempFolder + "\project.json"
        $projectJson = Get-Content $projectJsonPath | Out-String | ConvertFrom-Json
        
        $name = $projectJson.name
        $targetFramework = $projectJson.TargetFramework
        $expressionLanguage = $projectJson.ExpressionLanguage

        Start-Process -FilePath "`"$studioPath`"" -ArgumentList "`"$projectJsonPath`""

        $shellLogFile = Get-ChildItem -Path $logsPath -Filter "*_UiPath.Studio.log" | Select-Object -First 1

        while ($shellLogFile -eq $null -or !(Select-String -Path $shellLogFile -Pattern "process side open complete" | Select-Object -Last 1)) {
            $elapsed = ((Get-Date) - $startTime).TotalSeconds
            if ($elapsed > $timeoutPerRunInSeconds) {
                break
            }

            Start-Sleep -Seconds 1
            $shellLogFile = Get-ChildItem -Path $logsPath -Filter "*_UiPath.Studio.log" | Select-Object -First 1
        }

        $timestampString = "HH:mm:ss.fffffff"
        $regexPattern = '^\d{2}:\d{2}:\d{2}\.\d+'

        foreach ($label in $labels)
        {
            $beginLine = Select-String -Path $shellLogFile -Pattern "Begin $label" | Select-Object -ExpandProperty Line
            $endLine = Select-String -Path $shellLogFile -Pattern "End $label" | Select-Object -ExpandProperty Line
            
            $beginTimestampString = [regex]::Matches($beginLine, $regexPattern).Value
            $endTimestampString = [regex]::Matches($endLine, $regexPattern).Value

            $beginTimestamp = [DateTime]::ParseExact($beginTimestampString, $timestampString, $null)
            $endTimestamp = [DateTime]::ParseExact($endTimestampString, $timestampString, $null)
            $taskDuration = $endTimestamp.Subtract($beginTimestamp)

            $results += [PerformanceBenchmark]@{
                label = $label;
                projectName = $name;
                duration = $taskDuration;
                targetFramework = $targetFramework;
                expressionLanguage = $expressionLanguage;
            }
        }

        foreach ($result in $results)
        {
            Write-Host $result.ToString()
        }

        Kill-Studio 
        Remove-Item -Path $iterationTempFolder -Recurse -Force
    }

    $results | ConvertTo-Json | Out-File -FilePath "results.json"

}