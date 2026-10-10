$Endpoint = "http://localhost:4000/v1/chat/completions"
$BodyObj = @{
    model = "llama3"
    messages = @(
        @{
            role = "user"
            content = "Explain in two sentences how unified AI routing and GPU scheduling improve edge inference."
        }
    )
    max_tokens = 60
    temperature = 0.7
}
$JsonBody = $BodyObj | ConvertTo-Json -Compress

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $Response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body $JsonBody
    $Stopwatch.Stop()

    Write-Host "=== LiteLLM AI Gateway Response ===" -ForegroundColor Cyan
    Write-Host ($Response.choices[0].message.content) -ForegroundColor Green
    Write-Host "`nGateway Latency: $($Stopwatch.ElapsedMilliseconds) ms" -ForegroundColor Yellow
    Write-Host "Model Routed: $($Response.model)" -ForegroundColor Yellow
    Write-Host "Prompt Tokens: $($Response.usage.prompt_tokens)" -ForegroundColor Yellow
    Write-Host "Completion Tokens: $($Response.usage.completion_tokens)" -ForegroundColor Yellow
    $GenSpeed = [math]::Round(($Response.usage.completion_tokens / ($Stopwatch.ElapsedMilliseconds / 1000)), 2)
    Write-Host "Effective Throughput: ~$GenSpeed t/s" -ForegroundColor Cyan
} catch {
    Write-Host "Request failed: $_" -ForegroundColor Red
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Host "Server response: $($reader.ReadToEnd())" -ForegroundColor Red
    }
}
