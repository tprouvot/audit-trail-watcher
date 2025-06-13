public class AuditTrailWatcherBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

	DateTime lastRunDate;
	Map<String, List<Id>> groupNameToUserIds;
	EmailTemplate emailTemplate;
	String orgDomainUrl;
	Map<String, List<AuditTrailWatcherRule__c>> actionToRules = new Map<String, List<AuditTrailWatcherRule__c>>(); //action name / list of rules
	Map<Id, AuditTrailWatcherRule__c> ruleIdToRule = new Map<Id, AuditTrailWatcherRule__c>();
	Map<Id, List<SetupAuditTrail>> ruleToAuditRecords = new Map<Id, List<SetupAuditTrail>>();

	public AuditTrailWatcherBatch() {
		// Get the last successful run date
		List<AsyncApexJob> lastJob = [
			SELECT CompletedDate
			FROM AsyncApexJob
			WHERE ApexClass.Name = 'AuditTrailWatcherBatch'
			AND Status = 'Completed'
			ORDER BY CompletedDate DESC
			LIMIT 1
		];

		lastRunDate = !lastJob.isEmpty() ? lastJob[0].CompletedDate : null;

		List<AuditTrailWatcherRule__c> activeRules = [
			SELECT Id, Name, Action__c, GroupName__c, NotificationRecipient__c, SendPlatformEvent__c, Severity__c, Operator__c, Value__c
			FROM AuditTrailWatcherRule__c
			WHERE IsActive__c = true ORDER BY Action__c
		];

		//exit if no active rules
		if(activeRules.isEmpty()){
			return;
		}

		ruleIdToRule = new Map<Id, AuditTrailWatcherRule__c>(activeRules);

		Set<String> allGroupNames = new Set<String>();
		// Get unique actions from active rules and group names
		for(AuditTrailWatcherRule__c rule : activeRules) {
			//create actionToRules map
			List<AuditTrailWatcherRule__c> rules = actionToRules.get(rule.Action__c);
			if(rules == null) {
				rules = new List<AuditTrailWatcherRule__c>();
				actionToRules.put(rule.Action__c, rules);
			}
			rules.add(rule);

			if(String.isNotBlank(rule.GroupName__c)) {
				allGroupNames.addAll(rule.GroupName__c.split(','));
			}
		}

		// Get all group members at once
		groupNameToUserIds = new Map<String, List<Id>>();
		if(!allGroupNames.isEmpty()) {
			for(GroupMember member : [
				SELECT Group.DeveloperName, UserOrGroupId
				FROM GroupMember
				WHERE Group.DeveloperName IN :allGroupNames
				AND UserOrGroupId IN (
					SELECT Id
					FROM User
					WHERE IsActive = true
				)
			]) {
				List<Id> userIds = groupNameToUserIds.get(member.Group.DeveloperName);
				if(userIds == null) {
					userIds = new List<Id>();
					groupNameToUserIds.put(member.Group.DeveloperName, userIds);
				}
				userIds.add(member.UserOrGroupId);
			}
		}

		//get the main url for email redirection
		orgDomainUrl = URL.getOrgDomainURL().toExternalForm() + '/';

		// Get email template ID
		List<EmailTemplate> templates = [
			SELECT Id FROM EmailTemplate WHERE DeveloperName = 'AuditTrailWatcherNotification' LIMIT 1
		];
		if(!templates.isEmpty()) {
			emailTemplate = templates[0];
		}
	}

	public Database.QueryLocator start(Database.BatchableContext bc) {
		String query = 'SELECT Id, Action, Display, CreatedDate, CreatedById, CreatedBy.Username, Section, DelegateUser' +
					' FROM SetupAuditTrail';

		if(lastRunDate != null) {
			query += ' WHERE CreatedDate > :lastRunDate';
		}

		if(!actionToRules.isEmpty()) {
			Set<String> actionRulesSet = actionToRules.keySet();
			query += (lastRunDate != null ? ' AND' : ' WHERE') + ' Action IN :actionRulesSet';
		}
		query += ' ORDER BY Action, CreatedDate';
		return Database.getQueryLocator(query);
	}

	public void execute(Database.BatchableContext bc, List<SetupAuditTrail> scope) {

		// Process each audit trail record
		for(SetupAuditTrail audit : scope) {
			List<AuditTrailWatcherRule__c> rules = actionToRules.get(audit.Action);
			if(rules != null) {
				for(AuditTrailWatcherRule__c rule : rules) {
					// Group records by rule
					List<SetupAuditTrail> auditRecords = ruleToAuditRecords.get(rule.Id);
					if(auditRecords == null) {
						auditRecords = new List<SetupAuditTrail>();
						ruleToAuditRecords.put(rule.Id, auditRecords);
					}
					auditRecords.add(audit);
				}
			}
		}
	}

	public void finish(Database.BatchableContext bc) {
		List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
		List<AuditTrailWatcherEvent__e> eventsToPublish = new List<AuditTrailWatcherEvent__e>();

		// Prepare and send emails for each rule
		for(Id ruleId : ruleToAuditRecords.keySet()) {
			AuditTrailWatcherRule__c rule = ruleIdToRule.get(ruleId);

			if(rule != null) {
				// Prepare emails if needed
				if(String.isNotBlank(rule.GroupName__c) || rule.NotificationRecipient__c != null) {
					emailsToSend.addAll(prepareEmail(rule, ruleToAuditRecords.get(ruleId)));
				}

				// Prepare platform events if needed
				if(rule.SendPlatformEvent__c) {
					eventsToPublish.add(preparePlatformEvent(rule, ruleToAuditRecords.get(ruleId)));
				}
			}
		}

		if(!emailsToSend.isEmpty()) {
			Messaging.sendEmail(emailsToSend);
		}

		if(!eventsToPublish.isEmpty()) {
			EventBus.publish(eventsToPublish);
		}
	}

	public void execute(SchedulableContext sc) {
		Database.executeBatch(this);
	}

	private List<Messaging.SingleEmailMessage> prepareEmail(AuditTrailWatcherRule__c rule, List<SetupAuditTrail> auditRecords) {
		Set<Id> recipientIds = new Set<Id>();

		// Add direct recipient if specified
		if(rule.NotificationRecipient__c != null) {
			recipientIds.add(rule.NotificationRecipient__c);
		}

		// Add group members if specified
		if(String.isNotBlank(rule.GroupName__c)) {
			Set<String> groupNames = new Set<String>(rule.GroupName__c.split(','));
			for(String groupName : groupNames) {
				List<Id> userIds = groupNameToUserIds.get(groupName);
				if(userIds != null) {
					recipientIds.addAll(groupNameToUserIds.get(groupName));
				}
			}
		}

		// Build table content with scrollable wrapper and Action as a link
		String tableContent = '<table style="min-width:700px;"><thead><tr>';
		tableContent += '<th>Action</th>';
		tableContent += '<th>Display</th>';
		tableContent += '<th>Section</th>';
		tableContent += '<th>Created Date</th>';
		tableContent += '<th>Created By</th>';
		tableContent += '<th>Delegate User</th>';
		tableContent += '</tr></thead>';
		tableContent += '<tbody>';

		for(SetupAuditTrail audit : auditRecords) {
			tableContent += '<tr>';
			// Action as a hyperlink to the rule record
			tableContent += '<td><a href=' + orgDomainUrl + rule.Id + ' style="color:#0070d2;text-decoration:underline;">' + audit.Action + '</a></td>';
			tableContent += '<td>' + audit.Display + '</td>';
			tableContent += '<td>' + audit.Section + '</td>';
			tableContent += '<td>' + audit.CreatedDate.format() + '</td>';
			tableContent += '<td>' + audit.CreatedBy.Username + '</td>';
			tableContent += '<td>' + (audit.DelegateUser != null ? audit.DelegateUser : '') + '</td>';
			tableContent += '</tr>';
		}
		tableContent += '</tbody></table>';

		// Create email messages for each recipient
		List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
		for(Id recipientId : recipientIds) {
			// Render the template with the rule as the whatId
			Messaging.SingleEmailMessage mail = Messaging.renderStoredEmailTemplate(
				emailTemplate.Id,
				recipientId, // whoId
				rule.Id // whatId
			);
			// Replace the table content placeholder with actual content
			mail.setHtmlBody(mail.getHtmlBody().replace('{TableContent}', tableContent));
			mail.setSaveAsActivity(false);
			emails.add(mail);
		}

		return emails;
	}

	private String buildDetailText(List<SetupAuditTrail> auditRecords) {
		String detail = '';
		for(SetupAuditTrail audit : auditRecords) {
			detail += 'Created By: ' + audit.CreatedBy.Username + ' (' + audit.CreatedById + ')\n';
			detail += 'Display: ' + audit.Display + '\n';
			detail += 'Section: ' + audit.Section + '\n';
			if(audit.DelegateUser != null) {
				detail += 'Delegate User: ' + audit.DelegateUser + '\n';
			}
			detail += 'Created Date: ' + audit.CreatedDate + '\n\n';
		}
		return detail;
	}

	private AuditTrailWatcherEvent__e preparePlatformEvent(AuditTrailWatcherRule__c rule, List<SetupAuditTrail> auditRecords) {
		// Build detailed message
		String detail = '';
		for(SetupAuditTrail audit : auditRecords) {
			detail += 'Created By: ' + audit.CreatedBy.Username + ' (' + audit.CreatedById + ')\n';
			detail += 'Display: ' + audit.Display + '\n';
			detail += 'Section: ' + audit.Section + '\n';
			if(audit.DelegateUser != null) {
				detail += 'Delegate User: ' + audit.DelegateUser + '\n';
			}
		}
		SetupAuditTrail mainAuditRecord = auditRecords[0];
		//TODO check for platform event size to prevent error with 1mb limit
		return new AuditTrailWatcherEvent__e(
			Action__c = rule.Action__c,
			Detail__c = detail,
			Section__c = mainAuditRecord.Section,
			CreatedById__c = mainAuditRecord.CreatedById,
			DelegateUser__c = mainAuditRecord.DelegateUser,
			Severity__c = rule.Severity__c
		);
	}

	private Boolean evaluateRuleCondition(String operator, String value, String fieldValue) {
		if(fieldValue == null) fieldValue = '';
		if(value == null) value = '';
		switch on operator {
			when 'Equals' {
				return fieldValue == value;
			}
			when 'NotEquals' {
				return fieldValue != value;
			}
			when 'Contains' {
				return fieldValue.contains(value);
			}
			when 'NotContains' {
				return !fieldValue.contains(value);
			}
			when 'StartsWith' {
				return fieldValue.startsWith(value);
			}
			when 'NotStartsWith' {
				return !fieldValue.startsWith(value);
			}
			when 'EndsWith' {
				return fieldValue.endsWith(value);
			}
			when 'NotEndsWith' {
				return !fieldValue.endsWith(value);
			}
			when 'isEmpty' {
				return String.isBlank(fieldValue);
			}
			when 'isNotEmpty' {
				return !String.isBlank(fieldValue);
			}
			when else {
				return true;
			}
		}
	}
}