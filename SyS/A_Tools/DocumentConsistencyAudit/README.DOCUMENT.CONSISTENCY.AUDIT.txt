DOCUMENT CONSISTENCY AUDIT — CORE HARDENED MVP

Purpose
-------
Provide a read-only, deterministic audit capability for one declared project root.

Core rules
----------
1. ProjectRoot is a hard boundary.
2. StatePath and ChangedPaths must stay under ProjectRoot.
3. Paths that traverse junctions, symlinks or other reparse points are rejected.
4. HUMAN is mandatory. WHOAMI and BATON are optional.
5. Role resolution precedence is:
   - ROLE.<PROJECT_ID>.md/.txt
   - ROLE.md/.txt
   - other ROLE.*.md/.txt
6. Equal-precedence ambiguity is a HARD_CONFLICT.
7. AcceptedSessionContinue is the only input that increments the cadence counter.
8. Full audit cadence is exact: sessions 5, 10, 15, ...
9. Critical changes or explicit human request may force full mode without resetting cadence.
10. Findings are proposals only. The runner never mutates HUMAN, GRC, BUILD, registry or code.
11. The runner may recommend 05.SkillsMachineUpdate, but automatic execution is always false.
12. NoStateWrite must not create state, directories or other filesystem mutations.

Normalized state failures
-------------------------
STATE_JSON_INVALID
STATE_SCHEMA_VERSION_UNSUPPORTED
STATE_PROJECT_ID_MISMATCH
STATE_PROJECT_ROOT_MISMATCH
STATE_NEGATIVE_COUNTER
STATE_DUE_SESSION_BEHIND_COUNTER

Default full-scan exclusions
----------------------------
.git
node_modules
.venv
venv
dist
build
bin
obj
cache
caches
backup
backups
temp
tmp

PowerShell compatibility
------------------------
- The runner and test must parse in Windows PowerShell 5.1.
- PowerShell 7 parse is validated when a runnable pwsh host is available.

MVP boundary
------------
- The core resolves authority documents, cadence, root isolation, state validation and deterministic output.
- Deep semantic contradiction analysis between arbitrary documents remains outside MVP.
- No BUILD integration, registry mutation or validator mutation is performed by this core.

Consumer contract
-----------------
- Top-level `status` is normalized as `PASS`, `WARNING` or `HARD_CONFLICT`.
- State-validation failures must be treated by consumers as `STATE_ERROR`.
- Cross-root, rooted-path and reparse-point failures must be treated by consumers as `ROOT_SCOPE_VIOLATION`.

Workflow integration
--------------------
- `03.SESSION_CONTINUE`: run a focused audit before accepting continuity with `AcceptedSessionContinue=false`; rerun with `AcceptedSessionContinue=true` only after acceptance is confirmed.
- `04.REPOSITORY_STRUCTURE_REPAIR`: run a full audit before proposing or applying repair; `HARD_CONFLICT` blocks mutation but not diagnosis.
- `05.SkillsMachineUpdate`: may consume findings as read-only preflight and must block mutation when unresolved critical conflicts exist.
Path-aware project authority
----------------------------
- Role candidates must belong to the audited project root scope.
- Nested labs, generated use cases and internal source trees do not compete as root-project HUMAN/WHOAMI/BATON authorities.
- README-style files are descriptive and never role authority.
- Genuine equal-precedence ambiguity inside the same project scope remains a HARD_CONFLICT.
