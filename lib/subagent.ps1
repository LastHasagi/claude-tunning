#Requires -Version 5.1
<#
    subagent.ps1 — Install feature-card-handoff subagent/skill for Claude Code and Cursor.
    Do not run directly; dot-sourced by setup.ps1.
#>
function Get-FeatureCardSkillContent {
    return @'
---
name: feature-card-handoff
description: Create and maintain feature handoff cards in docs/feature/{feature-name}.md with DOR, DOD, requirements, acceptance criteria, risks, test plan, and review checklist. Use when implementing, fixing, or updating any feature across projects.
---

# Feature Card Handoff

## Purpose
Ensure every feature has a handoff card for developer review in `docs/feature/{feature-name}.md`.

## When To Use
- New feature implementation
- Feature changes during refactor
- Bugfix that changes feature behavior

## Mandatory Workflow
1. Infer or ask for `feature-name` in kebab-case.
2. Ensure folder `docs/feature/` exists.
3. Create or update `docs/feature/{feature-name}.md`.
4. Keep the card aligned with code changes while implementing.
5. Before finishing, verify DOR and DOD are explicit and testable.

## Card Template
Use this structure exactly:

```markdown
# Feature Card: {Feature Title}

## Metadata
- Feature Name: `{feature-name}`
- Status: `draft | in-progress | review | done`
- Owner: `{name-or-team}`
- Reviewer: `{name-or-team}`
- Created At: `{YYYY-MM-DD}`
- Last Updated: `{YYYY-MM-DD}`

## Context
Short problem statement and business/technical context.

## Goals
- Goal 1
- Goal 2

## Non-Goals
- Out-of-scope 1
- Out-of-scope 2

## Requirements
### Functional
- [ ] Requirement 1
- [ ] Requirement 2

### Non-Functional
- [ ] Performance
- [ ] Security
- [ ] Observability

## DOR (Definition of Ready)
- [ ] Scope is clear and bounded.
- [ ] Dependencies identified.
- [ ] UX/API contracts defined (when applicable).
- [ ] Risks identified.
- [ ] Test strategy agreed.

## Implementation Notes
- Architecture/layers touched
- Data model changes
- API/UI contracts

## Acceptance Criteria
- [ ] Scenario 1 (Given/When/Then)
- [ ] Scenario 2 (Given/When/Then)

## DOD (Definition of Done)
- [ ] Code implemented and reviewed.
- [ ] Automated tests added/updated and passing.
- [ ] Manual validation completed.
- [ ] Docs updated.
- [ ] No critical regressions.

## Test Plan
- Unit:
- Integration:
- E2E/Manual:

## Risks and Mitigations
- Risk:
  - Mitigation:

## Open Questions
- Question 1

## Review Checklist (Dev Revision)
- [ ] Requirements are complete and unambiguous.
- [ ] DOR and DOD are objective and measurable.
- [ ] Edge cases are covered.
- [ ] Security and failure paths considered.
- [ ] Test plan is sufficient.
```

## Quality Rules
- Keep content concise and actionable.
- Avoid placeholders like "TBD" in final card.
- Every checklist item must be verifiable.
- Keep terminology consistent with project architecture.

## Output Contract
When finishing feature work, include in your response:
- Card path created/updated.
- Short list of changed sections.
- Remaining open questions (if any).
'@
}
function Get-FeatureCardAgentContent {
    return @'
---
name: feature-card-handoff
description: Specialist that creates and updates feature cards in docs/feature/{feature-name}.md with DOR, DOD, requirements, acceptance criteria, and review checklist for developer revision.
model: gpt-5
tools:
  - read
  - edit
  - run
---

You are the Feature Card Handoff subagent.

For every feature implementation or feature-level bugfix:
1. Infer the feature slug in kebab-case (`feature-name`).
2. Create/update `docs/feature/{feature-name}.md`.
3. Fill sections with concrete and testable information:
   - Metadata
   - Context
   - Goals / Non-Goals
   - Requirements (functional and non-functional)
   - DOR (Definition of Ready)
   - Implementation Notes
   - Acceptance Criteria
   - DOD (Definition of Done)
   - Test Plan
   - Risks and Mitigations
   - Open Questions
   - Review Checklist
4. Keep the card synchronized with code changes during implementation.
5. At completion, report:
   - Card file path
   - Updated sections
   - Remaining open questions

Rules:
- Do not leave "TBD" placeholders in final output.
- Keep checklist items objective and verifiable.
- Match existing project architecture and naming conventions.
'@
}
function Write-TextFileUtf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content.Trim() + [Environment]::NewLine, $utf8)
}
function Get-SubagentInstallEntries {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$ProjectRoot
    )
    $items = [System.Collections.Generic.List[object]]::new()
    $targetNorm = $Target.Trim().ToLowerInvariant()
    $userProfile = $env:USERPROFILE

    if ($targetNorm -in @('claudecode','both','all')) {
        $items.Add([PSCustomObject]@{
            Label = 'Claude Code (global)'
            SkillPath = Join-Path $userProfile '.claude\skills\feature-card-handoff\SKILL.md'
            AgentPath = Join-Path $userProfile '.claude\agents\feature-card-handoff.md'
        }) | Out-Null
    }
    if ($targetNorm -in @('cursor','both','all')) {
        $items.Add([PSCustomObject]@{
            Label = 'Cursor (global)'
            SkillPath = Join-Path $userProfile '.cursor\skills\feature-card-handoff\SKILL.md'
            AgentPath = Join-Path $userProfile '.cursor\agents\feature-card-handoff.md'
        }) | Out-Null
    }
    if ($targetNorm -in @('project','all')) {
        $items.Add([PSCustomObject]@{
            Label = 'Project (.claude local)'
            SkillPath = Join-Path $ProjectRoot '.claude\skills\feature-card-handoff\SKILL.md'
            AgentPath = Join-Path $ProjectRoot '.claude\agents\feature-card-handoff.md'
        }) | Out-Null
        $items.Add([PSCustomObject]@{
            Label = 'Project (.cursor local)'
            SkillPath = Join-Path $ProjectRoot '.cursor\skills\feature-card-handoff\SKILL.md'
            AgentPath = Join-Path $ProjectRoot '.cursor\agents\feature-card-handoff.md'
        }) | Out-Null
    }

    return ,$items.ToArray()
}
function Invoke-SubagentSetupPhase {
    param(
        [string]$Target = 'Both',
        [string]$ScriptRoot = ''
    )
    Write-StepHeader 'Phase 5 — Subagent setup'
    if ([string]::IsNullOrWhiteSpace($Target)) {
        $Target = Show-SubagentTargetMenu
    }
    if ([string]::IsNullOrWhiteSpace($Target)) {
        Write-Info 'Subagent setup skipped.'
        return
    }

    $projectRoot = if ([string]::IsNullOrWhiteSpace($ScriptRoot)) { (Get-Location).Path } else { $ScriptRoot }
    $entries = Get-SubagentInstallEntries -Target $Target -ProjectRoot $projectRoot
    if ($entries.Count -eq 0) {
        Write-Info "No valid subagent target selected: $Target"
        return
    }

    $skillContent = Get-FeatureCardSkillContent
    $agentContent = Get-FeatureCardAgentContent

    foreach ($entry in $entries) {
        try {
            Write-Info "Configuring $($entry.Label)"
            Write-TextFileUtf8NoBom -Path $entry.SkillPath -Content $skillContent
            Write-TextFileUtf8NoBom -Path $entry.AgentPath -Content $agentContent
            Write-Ok "Skill  → $($entry.SkillPath)"
            Write-Ok "Agent  → $($entry.AgentPath)"
            Write-Host ''
        } catch {
            Write-Fail "Failed for $($entry.Label): $_"
        }
    }
}
