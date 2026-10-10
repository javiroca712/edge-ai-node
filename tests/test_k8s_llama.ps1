$Endpoint = "http://100.104.80.65:8083/v1/chat/completions"
$BodyObj = @{
    model = "Meta-Llama-3.1-8B-Instruct"
    messages = @(
        @{
            role = "user"
            content = "Explain why running LLM inference inside Kubernetes on AMD GPUs is efficient. Keep it concise."
        }
    )
    max_tokens = 100
    temperature = 0.7
}
$JsonBody = $BodyObj | ConvertTo-Json -Compress

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Response = Invoke-RestMethod -Uri $Endpoint -Method Post -ContentType "application/json" -Body $JsonBody
$Stopwatch.Stop()

Write-Host "=== K3s Containerized LLM Response ===" -ForegroundColor Cyan
Write-Host ($Response.choices[0].message.content) -ForegroundColor Green
Write-Host "`nLatency: $($Stopwatch.ElapsedMilliseconds) ms" -ForegroundColor Yellow
Write-Host "Prompt Tokens: $($Response.usage.prompt_tokens)" -ForegroundColor Yellow
Write-Host "Completion Tokens: $($Response.usage.completion_tokens)" -ForegroundColor Yellow
$GenSpeed = [math]::Round(($Response.usage.completion_tokens / ($Stopwatch.ElapsedMilliseconds / 1000)), 2)
Write-Host "Generation Throughput: ~$GenSpeed t/s" -ForegroundColor Cyan
