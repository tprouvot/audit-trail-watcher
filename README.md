# Audit Trail Watcher Framework

This framework allows Salesforce admins to configure rules to monitor Setup Audit Trail events and notify users or systems based on customizable conditions.

<img width="1417" height="855" alt="Audit Trail Watcher" src="https://github.com/user-attachments/assets/05eae8a6-9d75-4513-8453-3aec8af451d7" />

## Disclaimer

Audit Trail Watcher is not an official Salesforce product, and has not been officially tested or documented by Salesforce.

## Architecture

Rules are defined on the parent object `AuditTrailWatcherRule__c`. The **Action** field on the parent specifies which Setup Audit Trail action to monitor. Each rule can have multiple **conditions** stored as child records on `AuditTrailWatcherRuleCondition__c`; conditions define additional criteria (Source Field, Operator, Value). The parent defines how to combine them (AND, OR, or Custom formula) and where to send notifications.

## Object Reference

### Audit Trail Watcher Rule (Parent)

| Field | Type | Description |
|-------|------|-------------|
| **Name** | Text | Rule name (e.g., "ChangedApexClass"). |
| **Active** | Checkbox | When checked, the rule is evaluated by the batch. Inactive rules are skipped. Default: true. |
| **Notification Recipient** | Lookup (User) | User who receives email notifications when the rule is triggered. |
| **Group Names** | Text | Comma-separated developer names of Public Groups or Queues that receive notifications. Example: `AuditWatcher,SupportQueue`. |
| **Send Platform Event** | Checkbox | When checked, publishes an `AuditTrailWatcherEvent__e` platform event when the rule is triggered. |
| **Track Activity** | Checkbox | When checked, creates an Event in the Activity section each time an alert email is sent. Default: false. |
| **Severity** | Picklist | Alert type used for email styling: Info, Warning, Critical. Default: Warning. |
| **Action** | Text | Setup Audit Trail action to monitor (e.g., `changedApexClass`, `suOrgAdminLogin`, `PermSetAssign`). Stored on the parent; matching is case-insensitive. When the rule has conditions, both Action and conditions must match; when no conditions exist, only the action is tested. |
| **Logic Type** | Picklist (required) | How to combine condition results: **AND** (all must match), **OR** (any must match), or **Custom** (use formula below). |
| **Custom Logic** | Text | When Logic Type is Custom, a formula combining condition numbers with AND/OR. Example: `(1 OR 2) AND 3`. Only digits, AND, OR, parentheses, and spaces allowed. |

**Behavior:**

- At least one of **Notification Recipient** or **Group Names** must be set for email notifications.
- **Track Activity** creates an Event on the rule record when an email is sent, visible in the Activity related list.
- **Logic Type** and **Custom Logic** control how multiple conditions are evaluated (see Rule Conditions below).

### Audit Trail Watcher Rule Condition (Child)

| Field | Type | Description |
|-------|------|-------------|
| **Audit Trail Watcher Rule** | Master-Detail | Parent rule. |
| **Condition Number** | Number (required) | Unique number per rule (1, 2, 3…) used in Custom Logic formulas. |
| **Source Field** | Text | Setup Audit Trail field name to evaluate (e.g. Display, Section, DelegateUser). When empty, Display is used. Orgs may have different fields. |
| **Operator** | Picklist | How to compare the audit record’s Source Field (Display, Section, or DelegateUser): Equals, NotEquals, Contains, NotContains, StartsWith, NotStartsWith, EndsWith, NotEndsWith, isEmpty, isNotEmpty. |
| **Value** | Text | Value to compare against the Source Field (Display, Section, or DelegateUser) using the selected operator. |

**Behavior:**

- Each condition is evaluated against Setup Audit Trail records: the record’s **Action** must match, and the selected **Source Field (Display, Section, or DelegateUser)** is compared using **Operator** and **Value**.
- If Operator/Value are blank, the condition matches any record with the given Action (from the parent).
- Condition numbers must be unique per rule and are referenced in Custom Logic (e.g., `1 AND 2`).

## Rule Example

The following rule monitors Apex class changes and notifies the AuditWatcher group. The **Action** is configured on the parent; conditions refine the match.

![Audit Trail Watcher Rule example](docs/audit-trail-watcher-rule-example.png)

| Field | Value |
|-------|-------|
| **Rule Name** | Changed Apex Class |
| **Action** | changedApexClass |
| **Active** | ✓ |
| **Group Names** | AuditWatcher |
| **Send Platform Event** | ✓ |
| **Track Activity** | ✓ |
| **Severity** | Critical |
| **Logic Type** | Custom |
| **Custom Logic** | 1 AND 2 |

**Rule Conditions (2):**

| Condition Number | Source Field | Operator | Value |
|------------------|--------------|----------|-------|
| 1 | Field1 | Equals | AuditTrailWatcherBatch |
| 2 | Display | StartsWith | Changed |

**Behavior:** The rule triggers when a Setup Audit Trail record has `Action = changedApexClass` (from the parent) **and** both conditions match: Field1 equals `AuditTrailWatcherBatch` and Display starts with `Changed`. It sends an email to the AuditWatcher group, publishes a platform event, and creates an Event in the Activity section (visible in the screenshot).

## Logic Type Behavior

- **AND:** All conditions must match for the rule to trigger.
- **OR:** At least one condition must match.
- **Custom:** Use a formula like `(1 OR 2) AND 3` to combine condition results. Condition numbers refer to the Condition Number field on child records.

## Features

- **Rule-based monitoring:** Define rules with multiple conditions, similar to Transaction Security Policies.
- **Flexible condition evaluation:** Operators (Equals, Contains, StartsWith, etc.) evaluate the selected Source Field on each audit record.
- **Notifications:**
  - **Email:** Uses a customizable template with a table of matching audit records. Supports direct user and group recipients.
  - **Platform Event:** Publishes `AuditTrailWatcherEvent__e` for external integrations.
  - **Activity tracking:** Optional Event creation when emails are sent (Track Activity).
- **Batch and scheduling:** `AuditTrailWatcherBatch` processes only new audit records since the last run.
- **Permission set:** Included for admin access and notifications.

## How to Configure Rules

1. Create a rule on `AuditTrailWatcherRule__c`.
2. Set **Action** (parent field) to the Setup Audit Trail action to monitor (e.g., `changedApexClass`).
3. Set **Logic Type** (AND, OR, or Custom).
4. If Custom, enter **Custom Logic** (e.g., `(1 OR 2) AND 3`).
5. Add **Rule Conditions** (related list): for each condition, set Condition Number, Source Field (or leave default Display), Operator, and Value.
6. Set **Notification Recipient** and/or **Group Names** for email.
7. Optionally enable **Send Platform Event** and **Track Activity**.
8. Set **Severity** and activate the rule (**Active** = true).

## How to Run

```apex
// Look back 7 days (initial setup)
Database.executeBatch(new AuditTrailWatcherBatch(7));

// Process only new records since last run
Database.executeBatch(new AuditTrailWatcherBatch());

// Schedule (e.g., every hour)
System.schedule('AuditTrailWatcherSchedule', '0 0 * * * ?', new AuditTrailWatcherBatch());
```

## Email Template

The included email template shows a table of matching audit records. The Action column links to the rule record. Severity drives the alert styling.

## Platform Event

`AuditTrailWatcherEvent__e` is published when a rule matches and **Send Platform Event** is enabled. It includes action, section, user, and other details.

## Migration

If upgrading from the legacy single-condition model, run `scripts/migrate-rules-to-conditions.apex` before deploying the removal of the old Action/Operator/Value fields. See `scripts/README.md`.

## Deploy

```sh
sf project deploy start --source-dir force-app
```

## License

MIT license
