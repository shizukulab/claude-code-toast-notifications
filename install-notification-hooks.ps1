<#
Sets up Windows toast notifications for Claude Code:
  - Notification hook: fires for CLI notifications / idle prompts
  - Stop hook: fires when a turn/task completes
  - PermissionRequest hook: fires when Claude needs confirmation
    (this is the one that actually works inside the VSCode extension;
     the "Notification" hook does not fire there — see
     https://github.com/anthropics/claude-code/issues/11156)

Safe to re-run: skips any hook group that already contains a
BurntToast command, and merges into the existing settings.json
instead of overwriting it.
#>

param(
    [string]$SettingsPath = (Join-Path $HOME '.claude\settings.json')
)

$ErrorActionPreference = 'Stop'

# Pinned to a tested version so -Force (which skips the untrusted-repository
# prompt) can never silently pull in an unreviewed future release.
$burntToastVersion = '1.1.0'

if (-not (Get-Module -ListAvailable -Name BurntToast | Where-Object { $_.Version -eq [version]$burntToastVersion })) {
    Write-Host "Installing BurntToast $burntToastVersion..."
    Install-Module -Name BurntToast -RequiredVersion $burntToastVersion -Scope CurrentUser -Force
}

# Resolved at hook run-time (not baked into the command string) so this
# works regardless of where BurntToast ends up installed on this machine.
$resolveAndImport = '$mod = Get-Module -ListAvailable -Name BurntToast | Sort-Object Version -Descending | Select-Object -First 1; if (-not $mod) { exit 1 }; Import-Module $mod.Path -ErrorAction Stop'

$hookCommands = @{
    Notification = "`$d = [Console]::In.ReadToEnd() | ConvertFrom-Json; `$m = `$d.message; if (-not `$m) { `$m = 'Claude Code is waiting for input' }; $resolveAndImport; New-BurntToastNotification -Text 'Claude Code', `$m"
    Stop = "$resolveAndImport; New-BurntToastNotification -Text 'Claude Code', 'タスクが完了しました'"
    PermissionRequest = "`$d = [Console]::In.ReadToEnd() | ConvertFrom-Json; `$t = `$d.tool_name; `$m = if (`$t) { `"確認が必要です: `$t`" } else { 'Claude Code が確認を必要としています' }; $resolveAndImport; New-BurntToastNotification -Text 'Claude Code', `$m"
}

$settingsPath = $SettingsPath

$settings = if (Test-Path $settingsPath) {
    Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
} else {
    @{}
}
if (-not $settings.ContainsKey('hooks')) { $settings['hooks'] = @{} }

foreach ($event in $hookCommands.Keys) {
    if (-not $settings.hooks.ContainsKey($event)) { $settings.hooks[$event] = @() }

    $alreadyPresent = $settings.hooks[$event] | Where-Object {
        $_.hooks | Where-Object { $_.command -like '*BurntToastNotification*' }
    }
    if ($alreadyPresent) {
        Write-Host "Skipping $event (BurntToast hook already present)"
        continue
    }

    $settings.hooks[$event] += @{
        hooks = @(
            @{
                type    = 'command'
                shell   = 'powershell'
                command = $hookCommands[$event]
            }
        )
    }
    Write-Host "Added $event hook"
}

New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null
($settings | ConvertTo-Json -Depth 20) | Set-Content -Path $settingsPath -Encoding utf8

Write-Host "Done. Settings written to $settingsPath"
Write-Host 'Reload/restart Claude Code (and, if using the VSCode extension, run "Developer: Reload Window") for hooks to take effect.'
