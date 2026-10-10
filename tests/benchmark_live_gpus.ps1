# ==============================================================================
# Live Benchmark Suite: GPU 0 (PCIe 3.0 x8) vs GPU 1 (PCIe 3.0 x4)
# Executes identical payloads against live endpoints on ports 8082 and 8083
# ==============================================================================

$nodeHost = "100.104.80.65"
$portGPU0 = 8082
$portGPU1 = 8083

function Run-BenchmarkTest {
    param(
        [string]$TestName,
        [string]$PromptText,
        [int]$TokensToGenerate
    )

    Write-Host "========================================================================"
    Write-Host "Running Benchmark: $TestName (Generate: $TokensToGenerate tokens)"
    Write-Host "Prompt Length: $($PromptText.Length) chars (~$([math]::Round($PromptText.Length / 4)) tokens)"
    Write-Host "------------------------------------------------------------------------"

    $body = @{
        prompt = $PromptText
        n_predict = $TokensToGenerate
        temperature = 0.0
        stream = $false
    } | ConvertTo-Json -Depth 5

    # --- Test GPU 0 (PCIe x8) ---
    Write-Host "  -> Querying GPU 0 (Port $portGPU0 - PCIe 3.0 x8)..." -NoNewline
    $start0 = [System.Diagnostics.Stopwatch]::StartNew()
    $res0 = Invoke-RestMethod -Uri "http://${nodeHost}:${portGPU0}/completion" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
    $start0.Stop()
    Write-Host " Done ($($start0.ElapsedMilliseconds) ms)"

    # --- Test GPU 1 (PCIe x4) ---
    Write-Host "  -> Querying GPU 1 (Port $portGPU1 - PCIe 3.0 x4)..." -NoNewline
    $start1 = [System.Diagnostics.Stopwatch]::StartNew()
    $res1 = Invoke-RestMethod -Uri "http://${nodeHost}:${portGPU1}/completion" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 120
    $start1.Stop()
    Write-Host " Done ($($start1.ElapsedMilliseconds) ms)"

    # Extract llama.cpp internal timing metrics
    $pp_tokens = $res0.timings.prompt_n
    $tg_tokens = $res0.timings.predicted_n

    $pp_speed0 = [math]::Round($res0.timings.prompt_per_second, 2)
    $tg_speed0 = [math]::Round($res0.timings.predicted_per_second, 2)
    $pp_ms0    = [math]::Round($res0.timings.prompt_ms, 1)
    $tg_ms0    = [math]::Round($res0.timings.predicted_ms, 1)

    $pp_speed1 = [math]::Round($res1.timings.prompt_per_second, 2)
    $tg_speed1 = [math]::Round($res1.timings.predicted_per_second, 2)
    $pp_ms1    = [math]::Round($res1.timings.prompt_ms, 1)
    $tg_ms1    = [math]::Round($res1.timings.predicted_ms, 1)

    # Compute deltas
    $pp_diff_pct = [math]::Round((($pp_speed0 - $pp_speed1) / $pp_speed1) * 100, 2)
    $tg_diff_pct = [math]::Round((($tg_speed0 - $tg_speed1) / $tg_speed1) * 100, 2)

    [PSCustomObject]@{
        TestName        = $TestName
        PromptTokens    = $pp_tokens
        GenTokens       = $tg_tokens
        GPU0_PP_Speed   = "$pp_speed0 t/s"
        GPU1_PP_Speed   = "$pp_speed1 t/s"
        PP_DeltaPct     = "$pp_diff_pct %"
        GPU0_TG_Speed   = "$tg_speed0 t/s"
        GPU1_TG_Speed   = "$tg_speed1 t/s"
        TG_DeltaPct     = "$tg_diff_pct %"
        GPU0_Total_ms   = "$($start0.ElapsedMilliseconds) ms"
        GPU1_Total_ms   = "$($start1.ElapsedMilliseconds) ms"
    }
}

$results = @()

# 1. Short Payload
$shortPrompt = "Explain why the sky is blue and how Rayleigh scattering works in simple terms."
$results += Run-BenchmarkTest -TestName "Short Payload (Chat)" -PromptText $shortPrompt -TokensToGenerate 80

# 2. Medium Payload (~500 prompt tokens)
$mediumParagraph = @"
The Roman Empire was one of the greatest civilizations in history, spanning three continents and enduring for centuries. From the rise of Augustus following the fall of the Roman Republic to the tumultuous Pax Romana, Rome established legal, architectural, and political frameworks that continue to shape Western civilization. Legionaries maintained discipline and conquered vast territories, while engineering feats such as aqueducts, roads, and monumental amphitheaters unified diverse provinces. Trade flourished across the Mediterranean Sea, transforming it into an internal lake known as Mare Nostrum. However, internal political instability, economic inflation, barbarian migrations, and administrative fragmentation gradually eroded imperial power, culminating in the division into the Western and Eastern Roman Empires. Analyze the key military, economic, and institutional mechanisms that enabled Rome to maintain administrative control over this vast geographic expanse for centuries.
"@
$results += Run-BenchmarkTest -TestName "Medium Payload (500 tokens)" -PromptText $mediumParagraph -TokensToGenerate 100

# 3. Heavy Payload (~1500 prompt tokens)
$heavyParagraph = ($mediumParagraph + "`n`n") * 3 + "Summarize the primary thesis and identify three structural vulnerabilities that caused the eventual decline."
$results += Run-BenchmarkTest -TestName "Heavy Payload (1500 tokens)" -PromptText $heavyParagraph -TokensToGenerate 100

Write-Host ""
Write-Host "========================================================================"
Write-Host "                FINAL COMPARATIVE BENCHMARK MATRIX                      "
Write-Host "========================================================================"
$results | Format-Table -AutoSize

# Output as JSON for persistent reporting
$results | ConvertTo-Json -Depth 5 | Out-File "tests/benchmark_results.json"
