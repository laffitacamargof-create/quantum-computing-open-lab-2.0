# QuOLab Nexus — backup snapshot (2026-11-19)

- Source: https://github.com/laffitacamargof-create/quantum-computing-open-lab, branch `main`, commit `6c75afc79777d876f59b02695b7171382c3099a4`.
- Backup target: https://github.com/laffitacamargof-create/quantum-computing-open-lab-2.0, branch `backup/full-ecosystem-2026-11-19`.
- Supabase project: `QCOL2` (`rtkcfbnoqbivylejhspv`), region `us-east-2`, PostgreSQL 17.6.
- Database size at capture: 13,372,563 bytes (about 13 MB).
- Users: 48; user profiles: 48; API connection records: 0; user link records: 0; Supabase Storage objects: 0.
- Live migration history: 17 applied migrations.

## Included
- All source repository files are copied into this backup branch, retaining any pre-existing target-only files.
- `supabase/backup/live-schema-inventory.json`: current public/private application schema metadata, columns, defaults, constraints, indexes, RLS policies and triggers.
- `supabase/backup/live-migrations-2026-11-19.sql`: exact SQL statements recorded in the live migration history.

## Excluded for security
This target repository is PUBLIC. It does not contain Auth user rows, password hashes, recovery tokens, sessions, MFA data, personal user records, private files, API keys, Supabase service-role credentials, JWT signing secrets, OAuth tokens or other secret values. Those must be backed up to a private encrypted location, never committed as plaintext to a public repository.

## Not captured by PostgreSQL catalog export
Dashboard-level Auth providers, redirect URLs, SMTP configuration, JWT settings, project API keys, Edge Function secrets and network settings must be recorded/exported separately through Supabase Dashboard/CLI and stored securely.

## Recovery
This is a code + schema/migration configuration snapshot, not a complete physical PostgreSQL backup or point-in-time recovery image. To fully recover, prepare a new Supabase project, review/apply migrations in order, deploy Edge Functions, reconfigure dashboard-level settings and restore user data from a separate private encrypted database backup. Supabase-managed internal schemas must be restored using supported Supabase tooling, not by blindly replaying their internal definitions.
