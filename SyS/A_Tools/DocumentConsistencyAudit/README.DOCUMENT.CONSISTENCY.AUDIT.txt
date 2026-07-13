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
