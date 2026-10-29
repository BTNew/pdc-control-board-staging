-- r735 rollback: nothing to undo in behaviour; the WHERE true stays (removing it would only fail the repo lint).
-- To roll back the memo itself use the r732 rollback.
SELECT 'r735: no-op rollback' AS note;
