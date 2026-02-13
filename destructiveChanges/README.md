# Destructive Changes

Removes `Action__c`, `Operator__c`, and `Value__c` from `AuditTrailWatcherRule__c` (migrated to child `AuditTrailWatcherRuleCondition__c`).

**Prerequisite:** Run the migration script (`scripts/migrate-rules-to-conditions.apex`) first if you have existing rules with data in those fields.

The manifest deploys the refactored Apex classes first (so they no longer reference the parent fields), then runs destructive changes.

**Deploy destructive changes:**

```bash
sf project deploy start --manifest destructiveChanges/package.xml --post-destructive-changes destructiveChanges/destructiveChanges.xml
```
