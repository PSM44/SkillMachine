# AGENTS.md — PS.SkillsMachine Agent Guardrails
```
This repository is governed by human-controlled execution. AI agents must follow these rules before modifying files, running builds, committing, pushing, promoting canon, or requesting evidence.
```
## 1. Operating modes
```
### DETU is the default when uploads are available
```
DETU means:
```
1. Download executable.
2. Execute locally.
3. Upload a maximum of 10 consolidated files from Temp.
```
Use DETU whenever file upload is available.
```
### GPT.Upload.Lock is a temporary fallback
```
Use GPT.Upload.Lock only when uploads are unavailable, exhausted, unreliable, or explicitly activated by the human.
```
When GPT.Upload.Lock is active:
```
- Do not request uploads by default.
- Do not request the full repository.
- Do not request complete files unless explicitly authorized.
- Ask for specific pasteable evidence blocks of 9000 characters or less.
- Every runner must print TOVS_SUMMARY_START / TOVS_SUMMARY_END.
- Generated files may remain local on the human machine.
- Return to DETU when uploads become available unless the human explicitly extends GPT.Upload.Lock.
```
## 2. Required TOVS block under GPT.Upload.Lock
```
Every runner must emit a final pasteable block with:
```
- AI_TAIL_SCHEMA
- MB_ID
- FINAL_STATUS
- BLOCKER
- PROJECT_ROOT
- TEMP_PATH
- TOVS_ONLY_MODE=ON
- MAX_PASTE_CHARS=9000
- DB_MODIFIED
- CANON_MODIFIED
- COMMIT_PUSH_PERFORMED
- BUILD_EXECUTED
- WARNINGS
- KEY_FINDINGS
- DECISIONS_NEEDED
- NEXT_ACTION
```
FAIL must include an exact actionable BLOCKER.
```
PASS_WITH_REVIEW is allowed only for intermediate deliverables or explicitly accepted warnings.
```
## 3. Git safety
```
Never use:
```
```powershell
git add -A
```
```
Stage only explicit whitelisted files:
```
```powershell
git add -- "<exact path 1>" "<exact path 2>"
```
```
Before and after any repo-affecting action, check:
```
```powershell
git status --short --untracked-files=all
```
```
Hard stop on unexpected dirty scope.
```
Commits, pushes, builds, destructive actions, and canon promotion require explicit human authorization.
```
## 4. Path and shell safety
```
Quote paths containing spaces, especially under:
```
`	ext
C:\01. GitHub\Skills
```
```
When invoking PowerShell scripts, pass the full quoted script path to -File.
```
A prior failure mode was pwsh receiving only C:\01. because the path was split. This must not recur.
```
If an interactive PowerShell prompt enters >>, stop with Ctrl+C instead of continuing to paste.
```
## 5. Temp and local evidence
```
Use:
```
`	ext
C:\Users\aazcl\Downloads\Temp.SkillMachine
```
```
Do not clean Temp if it contains evidence required by current or prior steps.
```
Prefer timestamped subdirectories for runner outputs.
```
Under GPT.Upload.Lock, do not require upload of generated files. Request a compact TOVS or targeted Get-Content / Select-String evidence block.
```
## 6. Validation gates
```
Run and report relevant gates:
```
- SyS\A_Tools\Validation\Validate-System.ps1
- SyS\A_Tools\Radar\RADAR.ps1
- SyS\A_Tools\SessionClose\Test-SessionCloseReadiness.ps1
```
Before final session close or push-ready states, the expected standard is:
```
- Validate-System PASS
- RADAR PASS
- Readiness PASS
- repo clean
- local ahead/behind resolved unless intentionally pending
```
## 7. Candidate vs canon
```
New Skill/GRC opportunities are candidates unless the human explicitly authorizes canon promotion.
```
Use candidate locations such as:
```
`	ext
SkillsLake\99.CANDIDATES
GRCLake\99.CANDIDATES
```
```
Do not promote candidates to canon automatically.
```
## 8. SM-LAB-003 mandatory guardrails
```
The SM-LAB-003 matrix establishes these mandatory controls:
```
1. DETU default; GPT.Upload.Lock temporary fallback.
2. TOVS evidence under GPT.Upload.Lock.
3. No default dependency on uploads while GPT.Upload.Lock is active.
4. Explicit dirty scope with --untracked-files=all.
5. No git add -A.
6. Quote paths with spaces.
7. Validate/RADAR/Readiness evidence.
8. BATON/WHOAMI continuity before clean session close.
9. Candidate before canon.
10. AGENTS.md must derive from guardrail matrix.
11. Do not clean Temp if it contains required evidence.
12. Declare build execution status.
13. Human authorization for repo mutation.
14. Compact evidence requests under 9000 chars.
15. Exact failure semantics with actionable blockers.
```
## 9. Agent behavior
```
Agents must be conservative with repo mutations. When evidence is insufficient, ask for the smallest specific evidence block, not broad uploads or full files.
```
Agents must not assume current repository state from memory. Corroborate with current command evidence.
```
Agents must preserve Spanish operational style for this project unless the human requests otherwise.
```
## 10. Next expected SM-LAB-003 work
```
After this file is created, the next steps are expected to be:
```
1. Create GRC.GUARDRAILS.CORE candidate.
2. Create Skill guardrail candidate.
3. Validate matrix-to-artifact consistency.
4. Review, commit, and push only after explicit authorization.
```
## DETU upload package limit
```
Marker: MB-SM-057D-R2_DETU_MAX10_UPLOAD_PACK_RULE
```
When DETU is active, the assistant must consolidate all files it considers necessary into a maximum of 10 upload files.
```
This is an upper bound, not a target. A valid package can contain 1 to 10 files.
```
If there are more than 10 raw outputs, logs, reports, CSVs, manifests, diffs, stdout/stderr files, or evidence fragments, the runner must merge them into fewer consolidated files before asking the human to upload.
```
Required DETU package behavior:
```
- Create the package under Temp.
- Include a manifest.
- List only the files that must be uploaded.
- Keep FILES_COUNT <= 10.
- Do not ask for upload of files outside the manifest.
- If more than 10 files are required, consolidate first.
- If consolidation cannot be done, fail with BLOCKER=UPLOAD_PACK_OVER_LIMIT.
- Make every upload file self-explanatory for the IA.
```
The human should not have to repeat this rule.
```
## DETU Temp cleanup and upload-only package rule
```
Marker: MB-SM-057D-R3_TEMP_CLEAN_UPLOAD_ONLY_RULE
```
Before generating or adding files under the project Temp path, the runner must delete the existing contents of that Temp path.
```
For SkillsMachine the current Temp path is:
```
`	ext
C:\Users\aazcl\Downloads\Temp.SkillMachine
```
```
After the runner finishes, Temp must contain only the files the assistant wants the human to upload.
```
Operational consequences:
```
- Do not leave non-upload evidence, stray stdout/stderr, old package folders, previous manifests, or intermediate files in Temp.
- If the runner needs many raw outputs, merge them into consolidated upload files.
- The manifest must list all and only the files to upload.
- The upload pack must contain between 1 and 10 files.
- If Temp was not cleaned before use, acknowledge it as an operational non-compliance and correct it in the next iteration.
- Do not ask the human to choose which Temp files to upload; leave only the intended files there.
```
## SM-LAB-003 guardrail candidates
```
Marker: MB-SM-057E_GUARDRAIL_CANDIDATES_REFERENCE
```
SM-LAB-003 adds two guardrail candidates:
```
`	ext
GRCLake\99.CANDIDATES\GRC.GUARDRAILS.CORE.CANDIDATE.txt
SkillsLake\99.CANDIDATES\SKILL.AGENT_GUARDRAIL_DESIGN_AND_TESTING.CANDIDATE.txt
```
```
These candidates govern:
```
- DETU as the default method when uploads are available.
- GPT.Upload.Lock as fallback only.
- Temp cleanup before use.
- Final Temp containing only upload files.
- Maximum 10 upload files, not exactly 10.
- Consolidation/fusion of evidence when raw outputs exceed 10 files.
- No empty evidence files in upload packages.
- git status --short --untracked-files=all for dirty scope.
- No git add -A.
- Exact human authorization for commit, push, build, destructive actions, and canon promotion.
```
Candidate files must not be promoted to canon without explicit human authorization.
```
## DETU single upload subfolder rule
```
Marker: MB-SM-057E-R1_TEMP_SINGLE_UPLOAD_SUBFOLDER_RULE
```
For DETU workflows in this project:
```
- Use Temp root exactly as C:\Users\aazcl\Downloads\Temp.SkillMachine.
- Before using Temp, delete its existing contents.
- After the runner finishes, Temp root must contain exactly one upload subfolder.
- That upload subfolder must contain every file the assistant wants uploaded.
- Do not leave loose files directly under Temp.
- Do not leave multiple package folders under Temp.
- Do not leave nested subfolders inside the upload subfolder unless explicitly authorized.
- The upload subfolder must contain 1 to 10 files.
- If more evidence is needed, consolidate/merge before finishing.
- The human uploads the contents of that one subfolder, not arbitrary files from Temp.
```
