# Repository rules

- Add every newly created example or demo to the end of its user-visible example list. Do not insert new demos before existing entries.
- Prefer a clean structural refactor over incremental patches whenever the surrounding design can be simplified. Before finishing, remove duplicated logic, temporary compatibility branches, obsolete code paths, and workaround layers introduced by the change.
- Core modules may be refactored when they are the correct architectural boundary for a change. Before modifying core, explicitly notify the user of the reason, scope, and likely impact.
