# Audit Trail Watcher Framework

This framework allows Salesforce admins to configure rules to monitor Setup Audit Trail events and notify users or systems based on customizable conditions.

<img width="1417" height="823" alt="Audit Trail Watcher" src="https://github.com/user-attachments/assets/653a8e44-0dfa-4f5e-8017-afae975ddcfb" />


# Disclaimer

Audit Trail Watcher is not an official Salesforce product, and has not been officially tested or documented by Salesforce.

## Features

- **Rule-based Monitoring:**
  - Define rules in the custom object `AuditTrailWatcherRule__c` to monitor specific Setup Audit Trail actions.
  - Each rule can specify:
    - Action to monitor
    - Recipients (user or group)
    - Notification method (email, platform event)
    - Severity (for email styling)
    - Flexible condition (Operator/Value)
    - Active/inactive status

- **Flexible Condition Evaluation:**
  - Use the `Operator__c` picklist (Equals, NotEquals, Contains, NotContains, StartsWith, NotStartsWith, EndsWith, NotEndsWith, isEmpty, isNotEmpty) and `Value__c` to define when a rule should trigger based on the audit record's Display field.

- **Notifications:**
  - **Email:**
    - Uses a customizable email template with a dynamic table of matching audit records.
    - Supports both direct user and group recipients.
    - Severity is reflected in the email styling.
  - **Platform Event:**
    - Publishes an `AuditTrailWatcherEvent__e` event for integration with external systems.

- **Batch and Scheduled Execution:**
  - The `AuditTrailWatcherBatch` class can be run manually or scheduled to run periodically.
  - Only new audit records since the last run are processed.

- **Permission Set:**
  - Includes a permission set for easy assignment of required permissions to admins.

- **Extensible:**
  - Easily add new rules, actions, or notification types.

## How to Configure Rules

1. **Create a Rule:**
   - Go to the `AuditTrailWatcherRule__c` object and create a new record.
   - Set the `Action__c` to the Setup Audit Trail action you want to monitor (e.g., 'changedApexClass').
   - Set recipients via `NotificationRecipient__c` (User) or `GroupName__c` (Public Group).
   - Choose whether to send a platform event (`SendPlatformEvent__c`).
   - Set the severity for email styling.
   - Optionally, set `Operator__c` and `Value__c` to filter which audit records trigger the rule.
   - Activate the rule (`IsActive__c`).

2. **Assign Permission Set:**
   - Assign the included permission set to any admin who should manage or receive notifications.

## How to Run

- **Initial Setup:**
  - Before scheduling the batch, it's recommended to run it manually with a specific lookback period to process historical data:
    ```apex
    // Look back 7 days
    Database.executeBatch(new AuditTrailWatcherBatch(7));
    ```
  - This helps ensure you don't miss any important audit trail events from the past and allows you to verify your rules are working as expected.

- **Manual Run:**
  - Execute the batch class in Apex:
    ```apex
    // Process only new records since last run
    Database.executeBatch(new AuditTrailWatcherBatch());
    ```
- **Scheduled Run:**
  - Schedule the batch to run periodically:
    ```apex
    String sch = '0 0 * * * ?'; // every hour
    System.schedule('AuditTrailWatcherSchedule', sch, new AuditTrailWatcherBatch());
    ```

## Email Template

- The included email template displays a styled table of all matching audit records for each rule.
- The Action column is a clickable link to the rule record in Salesforce.
- The table is horizontally scrollable for wide content.

## Platform Event

- The `AuditTrailWatcherEvent__e` event is published for each rule that matches and is configured to send a platform event.
- The event includes details about the action, section, user, and more.

## Extending the Framework

- Add new fields to `AuditTrailWatcherRule__c` to support more complex conditions or notification types.
- Customize the batch class to support additional audit fields or notification logic.

## Deploy to Salesforce

Checkout the repo and deploy it with the new Salesforce CLI:

```sh
sf project deploy start --source-dir force-app
```

## About

This framework allows Salesforce admins to monitor and react to Setup Audit Trail events with flexible, rule-based notifications.

### License

MIT license
