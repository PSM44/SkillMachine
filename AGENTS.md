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
```text
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
External AI exchange temp (canonical):
```
```text
C:\Users\aazcl\Downloads\T.AI.SkillMachine
```
```
Rules for that path:
```
- FLAT only — subdirectories are forbidden.
- Purge contents before writing a new upload package.
- Leave only upload-ready files (prefer one consolidated TXT when possible).
- Minimum file count and total size.
- Do not store canon there.
```
```
Internal runtime scratch (validators, local work) is different and must not be treated as AI exchange.
Validate-System uses %TEMP%\SkillsMachine.Validation as internal scratch.
SyS\Temp and 90.USECASE\Temp are internal scratch/staging — classify before any rename.
```
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
```text
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
8. BATON cold-start continuity before clean session close; WHOAMI is not active product canon.
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
Before generating or adding files under the external AI exchange temp, the runner must delete the existing contents of that Temp path.
```
For SkillsMachine the current external AI exchange temp is:
```
```text
C:\Users\aazcl\Downloads\T.AI.SkillMachine
```
```
After the runner finishes, that Temp must contain only the files the assistant wants the human to upload.
```
Operational consequences:
```
- Flat root only — no subfolders.
- Do not leave non-upload evidence, stray stdout/stderr, old package folders, previous manifests, or intermediate files in Temp.
- If the runner needs many raw outputs, merge them into consolidated upload files.
- Prefer a single consolidated upload-ready TXT when feasible; never exceed 10 files.
- If Temp was not cleaned before use, acknowledge it as an operational non-compliance and correct it in the next iteration.
- Do not ask the human to choose which Temp files to upload; leave only the intended files there.
- Legacy path C:\Users\aazcl\Downloads\Temp.SkillMachine is superseded for AI exchange (may still exist only as unrelated local scratch — do not use it for DETU uploads).
```
## SM-LAB-003 guardrail candidates
```
Marker: MB-SM-057E_GUARDRAIL_CANDIDATES_REFERENCE
```
SM-LAB-003 adds two guardrail candidates:
```
```text
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
## DETU flat AI-exchange temp rule
```
Marker: MB-SM-057E-R1_TEMP_FLAT_AI_EXCHANGE_RULE
Supersedes: MB-SM-057E-R1_TEMP_SINGLE_UPLOAD_SUBFOLDER_RULE for SkillsMachine AI exchange
```
For DETU / AI-exchange workflows in this project:
```
- Use Temp root exactly as C:\Users\aazcl\Downloads\T.AI.SkillMachine.
- Before using Temp, delete its existing contents.
- Temp root must remain completely flat — subdirectories are forbidden.
- Place 1 to 10 upload-ready files directly under Temp root (prefer one consolidated file).
- Do not leave nested subfolders.
- If more evidence is needed, consolidate/merge before finishing.
- The human uploads those files from Temp root.
```
## PowerShell parser safety for generated runners

Marker: MB-SM-057J_POWERSHELL_PARSER_SAFETY_SKILL_REFERENCE

PowerShell `.ps1` runners must follow the candidate Skill:

```text
SkillsLake\99.CANDIDATES\SKILL.POWERSHELL_SCRIPT_PARSER_SAFETY.CANDIDATE.txt
```
Required controls before delivering long PowerShell runners:

- Scan for risky variable-colon patterns using regex `\$[A-Za-z_][A-Za-z0-9_]*:`.
- Exclude valid scoped variables only: `$env:`, `$script:`, `$global:`, `$local:`, `$private:`.
- Rewrite unsafe variable-colon cases using braces, for example `${HeadAfter}:`.
- Run a parser check when feasible before delivery.
- Deliver long scripts as `.ps1` files, not pasted console blocks.
- If a runner cleans Temp, it must refuse to run from Temp.
- Preserve DETU flat packaging under `C:\Users\aazcl\Downloads\T.AI.SkillMachine`.

Any non-allowed variable-colon match is a blocker before handing the runner to the human.


