# Repository rules

- Add every newly created example or demo to the end of its user-visible example list. Do not insert new demos before existing entries.
- Prefer a clean structural refactor over incremental patches whenever the surrounding design can be simplified. Before finishing, remove duplicated logic, temporary compatibility branches, obsolete code paths, and workaround layers introduced by the change.
- Core modules may be refactored when they are the correct architectural boundary for a change. Before modifying core, explicitly notify the user of the reason, scope, and likely impact.
- For every performance regression, follow `docs/performance_troubleshooting.md` before changing production behavior. The mandatory order is: enable comparable profile/release diagnostics, establish a native baseline, isolate layers with one-variable comparisons, identify the measured root cause, then implement the fix at the owning architectural boundary. Prefer a structural refactor over page-specific patches, and remove failed experiments and temporary workaround paths before finishing.
