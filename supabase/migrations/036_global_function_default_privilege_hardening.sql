-- Close the global PostgreSQL default-EXECUTE inheritance that schema-local
-- default ACL entries cannot override. Existing function ACLs are unchanged.
begin;

alter default privileges for role postgres
  revoke execute on functions from public, anon, authenticated;

commit;
