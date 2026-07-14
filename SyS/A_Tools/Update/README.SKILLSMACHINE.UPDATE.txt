SKILLSMACHINE UPDATE CORE MVP
=============================

STATUS:
MVP core runner. Not yet integrated with:
- 90.USECASE\BUILD.ps1
- 90.USECASE\05.SkillsMachineUpdate
- Start-SkillsMachine.ps1
- canonical validators

FILES:
- Invoke-SkillsMachineUpdate.ps1
- SKILLSMACHINE.PROJECT.BASELINE.schema.json
- SKILLSMACHINE.UPDATE.MANIFEST.schema.json
- Test-SkillsMachineUpdate.ps1
- README.SKILLSMACHINE.UPDATE.txt

SUPPORTED ACTIONS:
- preflight
- dry-run
- apply
- rollback

SUPPORTED UPDATE OPERATIONS:
- ADD
- REPLACE
- DELETE

HARD CONTROLS:
- Git repository required.
- Clean worktree required for preflight, dry-run and apply.
- DocumentConsistencyAudit may be used as a read-only preflight gate before mutation.
- Project baseline schema_version must be 1.1.
- created_by_skillsmachine must be true.
- Update manifest schema_version must be 1.1.
- All operations must be reversible.
- REPLACE and DELETE require backups.
- Dry-run fingerprint is mandatory for apply.
- Apply requires -HumanApproved.
- All paths must remain inside their permitted root.
- Baseline is updated only after all operations pass.
- Rollback restores affected files and the prior baseline.

EXCLUSIONS:
- No BUILD integration.
- No launcher integration.
- No support-package generation.
- No services, dependencies, secrets or private-data migration.
- No irreversible operations.
- No project not created by SkillsMachine.

PARTIAL-FAILURE CONTRACT:
If apply fails after one or more operations mutate the project, the runner automatically:
- loads the checkpoint manifest and ZIP;
- restores every affected target to its pre-apply state;
- removes files created by ADD;
- restores the prior baseline;
- verifies file and baseline hashes;
- emits APPLY_FAILED_ROLLBACK_PASS or APPLY_FAILED_ROLLBACK_FAIL.

Production readiness still requires BUILD, launcher, validator integration and repository-level
acceptance tests.

DOCUMENT CONSISTENCY PREFLIGHT:
- Optional flag: `-UseDocumentAuditPreflight`.
- The updater invokes `SyS\A_Tools\DocumentConsistencyAudit\Invoke-DocumentConsistencyAudit.ps1` in focused mode with `NoStateWrite=true`.
- Changed paths are derived from update target paths.
- `HARD_CONFLICT` blocks preflight/dry-run/apply.
- State failures are surfaced as `DOCUMENT_AUDIT_STATE_ERROR`.
- Root escapes or reparse traversal are surfaced as `DOCUMENT_AUDIT_ROOT_SCOPE_VIOLATION`.
- The updater never auto-resolves audit findings and never auto-executes itself from 03 or 04.

EXAMPLE:
1. Run dry-run and record DRY_RUN_FINGERPRINT.
2. Review the operation list.
3. Run apply with:
   -HumanApproved
   -ApprovedDryRunFingerprint <fingerprint>
4. Preserve CHECKPOINT_MANIFEST from output.
5. Run rollback with -CheckpointManifest when required.

TEST-ONLY FAILURE HOOK:
The environment variable SKILLSMACHINE_TEST_FAIL_AFTER_OPERATION_ID is accepted only when:
- the runner receives -TestMode;
- baseline.project_id starts with TEST_ or NEGATIVE_TEST_;
- the environment variable matches the current operation_id.

Without all three conditions, the hook is blocked. Normal projects cannot activate it.
Evidence and console output expose TEST_MODE_ACTIVE=True when the hook is used.
