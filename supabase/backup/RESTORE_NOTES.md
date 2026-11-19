# Supabase restore notes

Snapshot captured 2026-11-19 from project `rtkcfbnoqbivylejhspv`.

- `live-schema-inventory.json`: application table/column/index/constraint/RLS/trigger metadata for public/private schemas.
- `live-migrations-2026-11-19.sql`: exact statements from all live migration-history rows.

This is not a full data dump. Auth records, password hashes, sessions, personal user data, private files and credentials are intentionally excluded because the target repository is public.

Restore sequence:
1. Create a new Supabase project.
2. Review and apply migrations in version order, checking compatibility with the target Supabase version.
3. Deploy Edge Functions from `supabase/functions/`.
4. Reconfigure Auth providers, redirect URLs, SMTP, JWT settings and project secrets from their secure source of record.
5. Restore application/user data from a separate private encrypted backup.
6. Verify RLS, grants, triggers, functions, login and app workflows before switching traffic.

Never commit service-role keys, database passwords, JWT signing secrets or user exports here.
