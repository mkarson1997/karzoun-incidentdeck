param(
    [string]$Repository = "mkarson1997/karzoun-incidentdeck",
    [string]$ReleaseTag = "v0.1.0"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $lines = @(& gh @Arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "gh failed: gh $($Arguments -join ' ')"
    }

    $text = ($lines -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json
}

function Invoke-GhWithBody {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][object]$Body
    )

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("incidentdeck-" + [Guid]::NewGuid().ToString("N") + ".json")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        $json = $Body | ConvertTo-Json -Depth 30
        [IO.File]::WriteAllText($temp, $json, $utf8NoBom)
        return Invoke-GhJson @(
            "api",
            "--method", $Method,
            $Endpoint,
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            "--input", $temp
        )
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "IncidentDeck professional repository finalization" -ForegroundColor Cyan
Write-Host "Repository: $Repository"
Write-Host "Release:    $ReleaseTag"
Write-Host ""

& gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated."
}

$repo = Invoke-GhJson @("api", "repos/$Repository")
if ($repo.default_branch -ne "main") {
    throw "Expected default branch 'main', found '$($repo.default_branch)'."
}

$mainCommit = Invoke-GhJson @("api", "repos/$Repository/commits/main")
$mainSha = [string]$mainCommit.sha
Write-Host "Main SHA: $mainSha"

Write-Host "Verifying green CI Gate on main..." -ForegroundColor Cyan
$checks = Invoke-GhJson @(
    "api",
    "repos/$Repository/commits/$mainSha/check-runs",
    "-H", "Accept: application/vnd.github+json"
)
$ciGate = @(
    $checks.check_runs |
    Where-Object { $_.name -eq "CI Gate" -and $_.conclusion -eq "success" }
) | Select-Object -First 1
if ($null -eq $ciGate) {
    throw "CI Gate is not green for main SHA $mainSha."
}
Write-Host "  [OK] CI Gate is green" -ForegroundColor Green

Write-Host "Verifying $ReleaseTag release..." -ForegroundColor Cyan
try {
    $release = Invoke-GhJson @("api", "repos/$Repository/releases/tags/$ReleaseTag")
}
catch {
    throw "Release $ReleaseTag does not exist yet. Let the Release workflow finish successfully, then run this script again."
}

if ($release.draft -or $release.prerelease) {
    throw "Release $ReleaseTag must be a published non-prerelease release."
}

$tagRef = Invoke-GhJson @("api", "repos/$Repository/git/ref/tags/$ReleaseTag")
$releaseSha = [string]$tagRef.object.sha
if ($tagRef.object.type -eq "tag") {
    $annotatedTag = Invoke-GhJson @("api", "repos/$Repository/git/tags/$releaseSha")
    $releaseSha = [string]$annotatedTag.object.sha
}
if ($releaseSha -ne $mainSha) {
    throw "Release tag points to $releaseSha but verified main is $mainSha."
}

$assetNames = @($release.assets | ForEach-Object { [string]$_.name } | Sort-Object)
$expectedAssets = @("SHA256SUMS.txt", "incidentdeck-web-$ReleaseTag.tar.gz")
if (($assetNames -join "|") -ne ($expectedAssets -join "|")) {
    throw "Unexpected release assets. Found: $($assetNames -join ', ')"
}
foreach ($asset in @($release.assets)) {
    if ($asset.PSObject.Properties.Name -contains "digest") {
        $digest = [string]$asset.digest
        if ([string]::IsNullOrWhiteSpace($digest) -or -not $digest.StartsWith("sha256:")) {
            throw "Release asset '$($asset.name)' has no SHA-256 digest."
        }
    }
}
Write-Host "  [OK] release tag and assets verified" -ForegroundColor Green

Write-Host "Applying accurate repository metadata and merge policy..." -ForegroundColor Cyan
$repoPatch = @{
    description = "Offline-first Flutter incident response workspace with durable local state, explicit notification boundaries, deterministic synchronization, and conflict-safe revision handling."
    allow_squash_merge = $true
    allow_rebase_merge = $false
    allow_merge_commit = $false
    allow_auto_merge = $true
    delete_branch_on_merge = $true
    allow_update_branch = $true
}
$null = Invoke-GhWithBody "PATCH" "repos/$Repository" $repoPatch

$topics = @(
    "dart",
    "flutter",
    "offline-first",
    "local-first",
    "incident-response",
    "incident-management",
    "synchronization",
    "reliability",
    "conflict-resolution",
    "resilience"
)
$null = Invoke-GhWithBody "PUT" "repos/$Repository/topics" @{ names = $topics }
Write-Host "  [OK] metadata and topics applied" -ForegroundColor Green

Write-Host "Creating/updating active default-branch ruleset..." -ForegroundColor Cyan
$rulesetName = "Professional default branch"
$rulesetPayload = @{
    name = $rulesetName
    target = "branch"
    enforcement = "active"
    bypass_actors = @()
    conditions = @{
        ref_name = @{
            include = @("~DEFAULT_BRANCH")
            exclude = @()
        }
    }
    rules = @(
        @{ type = "deletion" },
        @{ type = "non_fast_forward" },
        @{ type = "required_linear_history" },
        @{
            type = "pull_request"
            parameters = @{
                required_approving_review_count = 0
                dismiss_stale_reviews_on_push = $false
                require_code_owner_review = $false
                require_last_push_approval = $false
                required_review_thread_resolution = $true
                allowed_merge_methods = @("squash")
            }
        },
        @{
            type = "required_status_checks"
            parameters = @{
                strict_required_status_checks_policy = $true
                do_not_enforce_on_create = $false
                required_status_checks = @(
                    @{ context = "CI Gate" }
                )
            }
        }
    )
}

$rulesets = @(Invoke-GhJson @("api", "repos/$Repository/rulesets"))
$existing = @(
    $rulesets |
    Where-Object { $_.name -eq $rulesetName -or $_.name -eq "Protect default branch" }
) | Select-Object -First 1

if ($null -ne $existing) {
    $rulesetId = [string]$existing.id
    $null = Invoke-GhWithBody "PUT" "repos/$Repository/rulesets/$rulesetId" $rulesetPayload
    Write-Host "  [OK] updated ruleset id=$rulesetId" -ForegroundColor Green
}
else {
    $created = Invoke-GhWithBody "POST" "repos/$Repository/rulesets" $rulesetPayload
    $rulesetId = [string]$created.id
    Write-Host "  [OK] created ruleset id=$rulesetId" -ForegroundColor Green
}

Write-Host "Cleaning merged milestone branches..." -ForegroundColor Cyan
$branchesToDelete = @(
    "feat/incidentdeck-v0.1-offline-core",
    "feat/local-durability-operational-ux",
    "feat/notification-boundary",
    "feat/offline-team-sync",
    "chore/v0.1.0-finalization"
)
foreach ($branch in $branchesToDelete) {
    $encodedRef = [Uri]::EscapeDataString("heads/$branch")
    & gh api --method DELETE "repos/$Repository/git/refs/$encodedRef" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  deleted $branch"
    }
    else {
        Write-Host "  skipped $branch (already absent or not deletable)"
    }
}

Write-Host "Verifying final ruleset and repository state..." -ForegroundColor Cyan
$finalRepo = Invoke-GhJson @("api", "repos/$Repository")
$finalTopics = Invoke-GhJson @("api", "repos/$Repository/topics")
$ruleset = Invoke-GhJson @("api", "repos/$Repository/rulesets/$rulesetId")

$ruleTypes = @($ruleset.rules | ForEach-Object { [string]$_.type })
$requiredRuleTypes = @("deletion", "non_fast_forward", "required_linear_history", "pull_request", "required_status_checks")
foreach ($ruleType in $requiredRuleTypes) {
    if ($ruleType -notin $ruleTypes) {
        throw "Ruleset verification failed. Missing rule: $ruleType"
    }
}

$statusRule = @($ruleset.rules | Where-Object { $_.type -eq "required_status_checks" }) | Select-Object -First 1
$contexts = @($statusRule.parameters.required_status_checks | ForEach-Object { [string]$_.context })
if ($contexts.Count -ne 1 -or $contexts[0] -ne "CI Gate") {
    throw "Ruleset must require exactly CI Gate."
}

$prRule = @($ruleset.rules | Where-Object { $_.type -eq "pull_request" }) | Select-Object -First 1
$mergeMethods = @($prRule.parameters.allowed_merge_methods)
if ($mergeMethods.Count -ne 1 -or $mergeMethods[0] -ne "squash") {
    throw "Ruleset must allow squash merging only."
}
if (-not $prRule.parameters.required_review_thread_resolution) {
    throw "Ruleset must require review-thread resolution."
}
if ($ruleset.enforcement -ne "active") {
    throw "Ruleset enforcement is not active."
}
if (@($ruleset.bypass_actors).Count -ne 0) {
    throw "Ruleset must not contain bypass actors."
}

if ($finalRepo.allow_merge_commit -or $finalRepo.allow_rebase_merge -or -not $finalRepo.allow_squash_merge) {
    throw "Repository merge settings are not squash-only."
}
if (-not $finalRepo.delete_branch_on_merge) {
    throw "delete_branch_on_merge is not enabled."
}
if ($finalTopics.names.Count -lt 7) {
    throw "Repository topics were not applied."
}

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host "IncidentDeck $ReleaseTag is verified at $mainSha, metadata is finalized, main is PR-only with strict CI Gate + resolved review threads + linear history, force-push/deletion are blocked, and merged milestone branches were cleaned." -ForegroundColor Cyan
