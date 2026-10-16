# Department 138 Pit intake

The current work-category classifier returns PIT_INSPECTION for Department 138 Pit and weigh. Native service preview and two storage constraints still used the earlier station list, rejecting genuine reports before intake.

This migration admits PIT_INSPECTION only for Department 138 in preview, service operations and unidentified review storage. All existing station values and Department 139 behavior remain. It changes no classifier, role grant, hours, approval, booking, QC or completion rule.

Staging verification exercised the genuine 48-row service partition for stocks 13018571 and 13018572 inside a rolled-back subtransaction. Both actual storage constraints passed allowed/denied cases for Department 138,139,135 and invalid stations. The preview fixture was absent afterward and the dedicated importer returned to its exact disabled state. Apply function, grants and function configuration remained unchanged. No source import was applied by installation.

Private source and receipts remain in the email-monitor workspace, work/review-20261016-0903. They are not included in this repository.
