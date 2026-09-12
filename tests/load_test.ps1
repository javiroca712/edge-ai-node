$uri = "http://localhost:4000/v1/chat/completions"
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer sk-1234"
}
$body = @{
    model = "llama3"
    messages = @(
        @{
            role = "user"
            content = "Write a comprehensive, extremely detailed 5000-word essay about the entire history of the Roman Empire, covering every single emperor and major battle in excruciating detail. Do not stop writing until the history is complete."
        }
    )
    max_tokens = 4000
} | ConvertTo-Json -Depth 10

Write-Host "Firing 4 concurrent massive requests to LiteLLM to saturate both GPUs..."

for ($i = 1; $i -le 4; $i++) {
    Start-Job -ScriptBlock {
        param($uri, $headers, $body, $i)
        Write-Host "Started Job $i"
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 300
            Write-Host "Job $i completed successfully."
        } catch {
            Write-Host "Job $i failed: $_"
        }
    } -ArgumentList $uri, $headers, $body, $i | Out-Null
}

Write-Host "All background load-generation jobs have been dispatched!"
Write-Host "Open Grafana and watch the metrics fly."
