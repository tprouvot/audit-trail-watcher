public class AuditTrailWatcherBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

	DateTime lastRunDate;
	Map<String, List<Id>> groupNameToUserIds;
	EmailTemplate emailTemplate;
	String orgDomainUrl;
	Map<String, Set<Id>> actionToRuleIds = new Map<String, Set<Id>>();
	Map<Id, AuditTrailWatcherRule__c> ruleIdToRule = new Map<Id, AuditTrailWatcherRule__c>();
	Map<Id, List<AuditTrailWatcherRuleCondition__c>> ruleToConditions = new Map<Id, List<AuditTrailWatcherRuleCondition__c>>();
	Set<String> auditFieldsToQuery = new Set<String>();

	@TestVisible
	Map<Id, List<SetupAuditTrail>> ruleToAuditRecords = new Map<Id, List<SetupAuditTrail>>();

	@TestVisible
	private AuditTrailSelector auditSelector;

	public AuditTrailWatcherBatch(Integer daysToLookBack) {
		this.lastRunDate = DateTime.now().addDays(-daysToLookBack);
		this.auditSelector = new AuditTrailSelector();
		initialize();
	}

	public AuditTrailWatcherBatch() {
		List<AsyncApexJob> lastJob = [
			SELECT CompletedDate
			FROM AsyncApexJob
			WHERE ApexClass.Name = 'AuditTrailWatcherBatch'
			AND Status = 'Completed'
			ORDER BY CompletedDate DESC
			LIMIT 1
		];

		this.lastRunDate = !lastJob.isEmpty() ? lastJob[0].CompletedDate : null;
		this.auditSelector = new AuditTrailSelector();
		initialize();
	}

	private void initialize() {
		List<AuditTrailWatcherRule__c> activeRules = [
			SELECT Id, Name, OwnerId, Action__c, GroupName__c, NotificationRecipient__c, SendPlatformEvent__c, Severity__c, LogicType__c, CustomLogic__c, TrackActivity__c,
				(SELECT ConditionNumber__c, Operator__c, Value__c, SourceField__c FROM AuditTrailWatcherRuleConditions__r ORDER BY ConditionNumber__c)
			FROM AuditTrailWatcherRule__c
			WHERE IsActive__c = true AND Action__c != null
		];

		if (activeRules.isEmpty()) {
			return;
		}

		ruleIdToRule = new Map<Id, AuditTrailWatcherRule__c>(activeRules);
		Set<String> allGroupNames = new Set<String>();

		for (AuditTrailWatcherRule__c rule : activeRules) {
			List<AuditTrailWatcherRuleCondition__c> conditions = rule.AuditTrailWatcherRuleConditions__r;
			if (conditions != null && !conditions.isEmpty()) {
				ruleToConditions.put(rule.Id, conditions);
				for (AuditTrailWatcherRuleCondition__c c : conditions) {
					if (String.isNotBlank(c.SourceField__c)) {
						String f = c.SourceField__c.trim();
						if (Pattern.matches('^[a-zA-Z0-9_.]+$', f)) {
							auditFieldsToQuery.add(f);
						}
					}
				}
			}

			String actionKey = rule.Action__c != null ? rule.Action__c.toLowerCase() : null;
			Set<Id> ruleIds = actionToRuleIds.get(actionKey);
			if (ruleIds == null) {
				ruleIds = new Set<Id>();
				actionToRuleIds.put(actionKey, ruleIds);
			}
			ruleIds.add(rule.Id);

			if (String.isNotBlank(rule.GroupName__c)) {
				allGroupNames.addAll(rule.GroupName__c.split(','));
			}
		}

		groupNameToUserIds = new Map<String, List<Id>>();
		if (!allGroupNames.isEmpty()) {
			for (GroupMember member : [
				SELECT Group.DeveloperName, UserOrGroupId
				FROM GroupMember
				WHERE Group.DeveloperName IN :allGroupNames
				AND UserOrGroupId IN (SELECT Id FROM User WHERE IsActive = true)
			]) {
				List<Id> userIds = groupNameToUserIds.get(member.Group.DeveloperName);
				if (userIds == null) {
					userIds = new List<Id>();
					groupNameToUserIds.put(member.Group.DeveloperName, userIds);
				}
				userIds.add(member.UserOrGroupId);
			}
		}

		orgDomainUrl = URL.getOrgDomainURL().toExternalForm() + '/';

		List<EmailTemplate> templates = [
			SELECT Id FROM EmailTemplate WHERE DeveloperName = 'AuditTrailWatcherNotification' LIMIT 1
		];
		if (!templates.isEmpty()) {
			emailTemplate = templates[0];
		}
	}

	public Iterable<SetupAuditTrail> start(Database.BatchableContext bc) {
		if (ruleIdToRule.isEmpty()) {
			return new List<SetupAuditTrail>();
		}
		Set<String> actions = actionToRuleIds.keySet();
		return auditSelector.getAuditTrailIterable(lastRunDate, actions, auditFieldsToQuery);
	}

	public void execute(Database.BatchableContext bc, List<SetupAuditTrail> scope) {
		for (SetupAuditTrail audit : scope) {
			String actionKey = audit.Action != null ? audit.Action.toLowerCase() : null;
			Set<Id> ruleIds = actionToRuleIds.get(actionKey);
			if (ruleIds == null) {
				continue;
			}

			for (Id ruleId : ruleIds) {
				AuditTrailWatcherRule__c rule = ruleIdToRule.get(ruleId);
				List<AuditTrailWatcherRuleCondition__c> conditions = ruleToConditions.get(ruleId);
				if (rule == null) {
					continue;
				}

				Boolean matches;
				if (conditions == null || conditions.isEmpty()) {
					matches = true;
				} else {
					Map<Decimal, Boolean> conditionResults = new Map<Decimal, Boolean>();
					for (AuditTrailWatcherRuleCondition__c cond : conditions) {
						String fieldValue = getAuditFieldValue(audit, cond.SourceField__c);
						Boolean condMatches = evaluateCondition(cond.Operator__c, cond.Value__c, fieldValue);
						conditionResults.put(cond.ConditionNumber__c, condMatches);
					}
					matches = evaluateRuleLogic(rule, conditionResults);
				}

				if (matches) {
					List<SetupAuditTrail> auditRecords = ruleToAuditRecords.get(ruleId);
					if (auditRecords == null) {
						auditRecords = new List<SetupAuditTrail>();
						ruleToAuditRecords.put(ruleId, auditRecords);
					}
					auditRecords.add(audit);
				}
			}
		}
	}

	private String getAuditFieldValue(SetupAuditTrail audit, String sourceField) {
		if (String.isBlank(sourceField)) {
			sourceField = 'Display';
		}
		try {
			Object val = audit.get(sourceField.trim());
			return val != null ? String.valueOf(val) : '';
		} catch (Exception e) {
			return '';
		}
	}

	public void finish(Database.BatchableContext bc) {
		List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
		List<AuditTrailWatcherEvent__e> eventsToPublish = new List<AuditTrailWatcherEvent__e>();
		List<Event> eventsToInsert = new List<Event>();

		for (Id ruleId : ruleToAuditRecords.keySet()) {
			AuditTrailWatcherRule__c rule = ruleIdToRule.get(ruleId);

			if (rule != null) {
				if (String.isNotBlank(rule.GroupName__c) || rule.NotificationRecipient__c != null) {
					emailsToSend.addAll(prepareEmail(rule, ruleToAuditRecords.get(ruleId)));
				}

				if (rule.SendPlatformEvent__c) {
					eventsToPublish.add(preparePlatformEvent(rule, ruleToAuditRecords.get(ruleId)));
				}

				if (rule.TrackActivity__c && (String.isNotBlank(rule.GroupName__c) || rule.NotificationRecipient__c != null)) {
					eventsToInsert.add(createActivityEvent(rule, ruleToAuditRecords.get(ruleId)));
				}
			}
		}

		if (!emailsToSend.isEmpty()) {
			Messaging.sendEmail(emailsToSend);
		}

		if (!eventsToPublish.isEmpty()) {
			EventBus.publish(eventsToPublish);
		}

		if (!eventsToInsert.isEmpty()) {
			insert eventsToInsert;
		}
	}

	public void execute(SchedulableContext sc) {
		Database.executeBatch(this);
	}

	private Boolean evaluateRuleLogic(AuditTrailWatcherRule__c rule, Map<Decimal, Boolean> conditionResults) {
		if (rule.LogicType__c == 'AND') {
			for (Boolean r : conditionResults.values()) {
				if (!r) {
					return false;
				}
			}
			return true;
		}

		if (rule.LogicType__c == 'OR') {
			for (Boolean r : conditionResults.values()) {
				if (r) {
					return true;
				}
			}
			return false;
		}

		if (rule.LogicType__c == 'Custom' && String.isNotBlank(rule.CustomLogic__c)) {
			return evaluateCustomLogic(rule.CustomLogic__c.trim(), conditionResults);
		}

		return false;
	}

	@TestVisible
	private static Boolean evaluateCustomLogic(String formula, Map<Decimal, Boolean> conditionResults) {
		if (String.isBlank(formula)) {
			return false;
		}
		String normalized = formula.toUpperCase().replaceAll('\\s+', ' ').trim();
		ParseResult pr = parseOr(normalized, 0, conditionResults);
		return pr.success && pr.pos >= normalized.length() ? pr.value : false;
	}

	private class ParseResult {
		Boolean value;
		Integer pos;
		Boolean success;

		ParseResult(Boolean value, Integer pos, Boolean success) {
			this.value = value;
			this.pos = pos;
			this.success = success;
		}
	}

	private static Integer skipSpaces(String expr, Integer pos) {
		while (pos < expr.length() && expr.substring(pos, pos + 1) == ' ') {
			pos++;
		}
		return pos;
	}

	private static ParseResult parseOr(String expr, Integer pos, Map<Decimal, Boolean> results) {
		ParseResult left = parseAnd(expr, pos, results);
		if (!left.success) {
			return left;
		}
		pos = left.pos;
		while (pos < expr.length()) {
			pos = skipSpaces(expr, pos);
			if (pos + 2 <= expr.length() && expr.substring(pos, pos + 2) == 'OR') {
				pos = skipSpaces(expr, pos + 2);
				ParseResult right = parseAnd(expr, pos, results);
				if (!right.success) {
					return right;
				}
				left = new ParseResult(left.value || right.value, right.pos, true);
				pos = right.pos;
			} else {
				break;
			}
		}
		return left;
	}

	private static ParseResult parseAnd(String expr, Integer pos, Map<Decimal, Boolean> results) {
		ParseResult left = parsePrimary(expr, pos, results);
		if (!left.success) {
			return left;
		}
		pos = left.pos;
		while (pos < expr.length()) {
			pos = skipSpaces(expr, pos);
			if (pos + 3 <= expr.length() && expr.substring(pos, pos + 3) == 'AND') {
				pos = skipSpaces(expr, pos + 3);
				ParseResult right = parsePrimary(expr, pos, results);
				if (!right.success) {
					return right;
				}
				left = new ParseResult(left.value && right.value, right.pos, true);
				pos = right.pos;
			} else {
				break;
			}
		}
		return left;
	}

	private static ParseResult parsePrimary(String expr, Integer pos, Map<Decimal, Boolean> results) {
		pos = skipSpaces(expr, pos);
		if (pos >= expr.length()) {
			return new ParseResult(false, pos, false);
		}
		if (expr.substring(pos, pos + 1) == '(') {
			ParseResult innerResult = parseOr(expr, pos + 1, results);
			if (!innerResult.success) {
				return innerResult;
			}
			pos = skipSpaces(expr, innerResult.pos);
			if (pos < expr.length() && expr.substring(pos, pos + 1) == ')') {
				return new ParseResult(innerResult.value, pos + 1, true);
			}
			return new ParseResult(false, pos, false);
		}
		Integer start = pos;
		while (pos < expr.length()) {
			String c = expr.substring(pos, pos + 1);
			if (c >= '0' && c <= '9') {
				pos++;
			} else {
				break;
			}
		}
		if (pos > start) {
			Decimal num = Decimal.valueOf(expr.substring(start, pos));
			Boolean val = results.get(num);
			return new ParseResult(val != null && val, pos, true);
		}
		return new ParseResult(false, pos, false);
	}

	private Boolean evaluateCondition(String operator, String value, String fieldValue) {
		if (fieldValue == null) {
			fieldValue = '';
		}
		if (value == null) {
			value = '';
		}
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

	private List<Messaging.SingleEmailMessage> prepareEmail(AuditTrailWatcherRule__c rule, List<SetupAuditTrail> auditRecords) {
		Set<Id> recipientIds = new Set<Id>();

		if (rule.NotificationRecipient__c != null) {
			recipientIds.add(rule.NotificationRecipient__c);
		}

		if (String.isNotBlank(rule.GroupName__c)) {
			Set<String> groupNames = new Set<String>(rule.GroupName__c.split(','));
			for (String groupName : groupNames) {
				List<Id> userIds = groupNameToUserIds.get(groupName.trim());
				if (userIds != null) {
					recipientIds.addAll(userIds);
				}
			}
		}

		String tableContent = '<table style="min-width:700px;"><thead><tr>';
		tableContent += '<th>Action</th><th>Display</th><th>Section</th><th>Created Date</th><th>Created By</th><th>Delegate User</th>';
		tableContent += '</tr></thead><tbody>';

		for (SetupAuditTrail audit : auditRecords) {
			tableContent += '<tr>';
			tableContent += '<td><a href=' + orgDomainUrl + rule.Id + ' style="color:#0070d2;text-decoration:underline;">' + audit.Action + '</a></td>';
			tableContent += '<td>' + audit.Display + '</td>';
			tableContent += '<td>' + audit.Section + '</td>';
			tableContent += '<td>' + audit.CreatedDate.format() + '</td>';
			tableContent += '<td>' + audit.CreatedBy.Username + '</td>';
			tableContent += '<td>' + (audit.DelegateUser != null ? audit.DelegateUser : '') + '</td>';
			tableContent += '</tr>';
		}
		tableContent += '</tbody></table>';

		List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
		for (Id recipientId : recipientIds) {
			Messaging.SingleEmailMessage mail = Messaging.renderStoredEmailTemplate(
				emailTemplate.Id,
				recipientId,
				rule.Id
			);
			mail.setHtmlBody(mail.getHtmlBody().replace('{TableContent}', tableContent));
			mail.setSaveAsActivity(false);
			mail.setOrgWideEmailAddressId('0D2J7000000wk58KAA');//TODO use setting or whatever to customize this
			emails.add(mail);
		}

		return emails;
	}

	private Event createActivityEvent(AuditTrailWatcherRule__c rule, List<SetupAuditTrail> auditRecords) {
		DateTime now = DateTime.now();
		String subject = 'Audit Trail Alert: ' + rule.Name + ' (' + auditRecords.size() + ' record' + (auditRecords.size() == 1 ? '' : 's') + ')';
		String description = '';
		for (SetupAuditTrail audit : auditRecords) {
			description += 'Action: ' + audit.Action + '\n';
			description += 'Display: ' + audit.Display + '\n';
			description += 'Section: ' + audit.Section + '\n';
			description += 'Created By: ' + audit.CreatedBy.Username + '\n';
			if (audit.DelegateUser != null) {
				description += 'Delegate User: ' + audit.DelegateUser + '\n';
			}
			description += 'Created Date: ' + audit.CreatedDate.format() + '\n\n';
		}
		return new Event(
			Subject = subject,
			WhatId = rule.Id,
			OwnerId = rule.OwnerId,
			StartDateTime = now,
			EndDateTime = now.addMinutes(1),
			Description = description
		);
	}

	private AuditTrailWatcherEvent__e preparePlatformEvent(AuditTrailWatcherRule__c rule, List<SetupAuditTrail> auditRecords) {
		String detail = '';
		for (SetupAuditTrail audit : auditRecords) {
			detail += 'Created By: ' + audit.CreatedBy.Username + ' (' + audit.CreatedById + ')\n';
			detail += 'Display: ' + audit.Display + '\n';
			detail += 'Section: ' + audit.Section + '\n';
			if (audit.DelegateUser != null) {
				detail += 'Delegate User: ' + audit.DelegateUser + '\n';
			}
		}
		SetupAuditTrail mainAuditRecord = auditRecords[0];
		return new AuditTrailWatcherEvent__e(
			Action__c = rule.Action__c != null ? rule.Action__c : mainAuditRecord.Action,
			Detail__c = detail,
			Section__c = mainAuditRecord.Section,
			CreatedById__c = mainAuditRecord.CreatedById,
			DelegateUser__c = mainAuditRecord.DelegateUser,
			Severity__c = rule.Severity__c
		);
	}
}
