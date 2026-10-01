DO $$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
     WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING environment required'; END IF;
END $$;
CREATE INDEX account_scopes_salesperson_idx ON pdc_sales_private.account_scopes(salesperson_id);
CREATE INDEX account_scopes_assigned_by_idx ON pdc_sales_private.account_scopes(assigned_by);
-- Explicit denial documents the owner-only private-table design.
CREATE POLICY account_scopes_no_direct_access ON pdc_sales_private.account_scopes
 FOR ALL TO authenticated USING(false) WITH CHECK(false);
