-- r733 rollback: takes the r733 regex back out of regression_checks_self_test. The 24 literal pin-total locks are not
-- restored (they broke the r529 rule). Staging cdsmnqxtyyoeoznmbidd only.
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
  $new$
     OR c.check_sql ~* $re7$(\mpins\.(n|pin_count)|\(\s*select\s+(n|pin_count)\s+from\s+pins\s*\)|\s+pins\s*\)|\mpin_count)\s*(=|<>|!=)\s*\(?\s*(select\s+)?[0-9]{3,}$re7$$new$, ''),
    description = replace(description, ' Since r733 it also catches a pin count compared to a three-digit literal through an alias (pins.n, pin_count).', '')
WHERE check_name = 'regression_checks_self_test';
