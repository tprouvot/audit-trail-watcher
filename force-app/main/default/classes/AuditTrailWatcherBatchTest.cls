@isTest
private class AuditTrailWatcherBatchTest {

	private class MockAuditTrailSelector extends AuditTrailSelector {
		private List<SetupAuditTrail> mockRecords;

		MockAuditTrailSelector(List<SetupAuditTrail> records) {
			this.mockRecords = records;
		}

		public override Iterable<SetupAuditTrail> getAuditTrailIterable(DateTime lastRunDate, Set<String> actions, Set<String> fieldsToQuery) {
			return mockRecords != null ? mockRecords : new List<SetupAuditTrail>();
		}
	}

	private static String buildMockAuditTrailJson(String action, String display, String section) {
		return buildMockAuditTrailJson(action, display, section, null);
	}

	private static String buildMockAuditTrailJson(String action, String display, String section, String delegateUser) {
		String createdDate = DateTime.now().addDays(-1).format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
		String delegateJson = delegateUser != null ? '"DelegateUser":"' + delegateUser + '"' : '"DelegateUser":null';
		return '[{"attributes":{"type":"SetupAuditTrail"},"Action":"' + action + '","Display":"' + display + '","Section":"' + section +
			'","CreatedById":"' + UserInfo.getUserId() + '",' + delegateJson + ',"CreatedDate":"' + createdDate +
			'","CreatedBy":{"attributes":{"type":"User"},"Username":"' + UserInfo.getUsername() + '"}}]';
	}

	@testSetup
	static void setup() {
		AuditTrailWatcherRule__c rule = new AuditTrailWatcherRule__c(
			Name = 'PermSetAssign Rule',
			Action__c = 'PermSetAssign',
			LogicType__c = 'AND',
			NotificationRecipient__c = UserInfo.getUserId(),
			SendPlatformEvent__c = true,
			Severity__c = 'Critical',
			IsActive__c = true,
			TrackActivity__c = true
		);
		insert rule;

		insert new AuditTrailWatcherRuleCondition__c(
			AuditTrailWatcherRule__c = rule.Id,
			ConditionNumber__c = 1,
			SourceField__c = 'Display',
			Operator__c = 'Contains',
			Value__c = 'Permission set'
		);

		AuditTrailWatcherRule__c orRule = new AuditTrailWatcherRule__c(
			Name = 'OR Rule',
			Action__c = 'PermSetAssign',
			LogicType__c = 'OR',
			NotificationRecipient__c = UserInfo.getUserId(),
			SendPlatformEvent__c = true,
			Severity__c = 'Critical',
			IsActive__c = true,
			TrackActivity__c = true
		);
		insert orRule;

		insert new List<AuditTrailWatcherRuleCondition__c>{
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = orRule.Id,
				ConditionNumber__c = 1,
				SourceField__c = 'Display',
				Operator__c = 'Contains',
				Value__c = 'Permission'
			),
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = orRule.Id,
				ConditionNumber__c = 2,
				SourceField__c = 'Section',
				Operator__c = 'Equals',
				Value__c = 'OtherSection'
			)
		};

		AuditTrailWatcherRule__c orNoMatchRule = new AuditTrailWatcherRule__c(
			Name = 'OR Rule No Match',
			Action__c = 'PermSetAssign',
			LogicType__c = 'OR',
			NotificationRecipient__c = UserInfo.getUserId(),
			SendPlatformEvent__c = true,
			Severity__c = 'Critical',
			IsActive__c = true,
			TrackActivity__c = true
		);
		insert orNoMatchRule;

		insert new List<AuditTrailWatcherRuleCondition__c>{
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = orNoMatchRule.Id,
				ConditionNumber__c = 1,
				SourceField__c = 'Display',
				Operator__c = 'Contains',
				Value__c = 'zzz'
			),
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = orNoMatchRule.Id,
				ConditionNumber__c = 2,
				SourceField__c = 'Section',
				Operator__c = 'Equals',
				Value__c = 'zzz'
			)
		};

		AuditTrailWatcherRule__c customRule = new AuditTrailWatcherRule__c(
			Name = 'Custom Logic Rule',
			Action__c = 'PermSetAssign',
			LogicType__c = 'Custom',
			CustomLogic__c = '1 OR 2',
			NotificationRecipient__c = UserInfo.getUserId(),
			SendPlatformEvent__c = true,
			Severity__c = 'Critical',
			IsActive__c = true,
			TrackActivity__c = true
		);
		insert customRule;

		insert new List<AuditTrailWatcherRuleCondition__c>{
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = customRule.Id,
				ConditionNumber__c = 1,
				SourceField__c = 'Display',
				Operator__c = 'Contains',
				Value__c = 'Permission'
			),
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = customRule.Id,
				ConditionNumber__c = 2,
				SourceField__c = 'Display',
				Operator__c = 'Contains',
				Value__c = 'zzz'
			)
		};

		AuditTrailWatcherRule__c operatorsRule = new AuditTrailWatcherRule__c(
			Name = 'Operators Rule',
			Action__c = 'PermSetAssign',
			LogicType__c = 'AND',
			NotificationRecipient__c = UserInfo.getUserId(),
			SendPlatformEvent__c = true,
			Severity__c = 'Critical',
			IsActive__c = true,
			TrackActivity__c = true
		);
		insert operatorsRule;

		insert new List<AuditTrailWatcherRuleCondition__c>{
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = operatorsRule.Id,
				ConditionNumber__c = 1,
				SourceField__c = 'Display',
				Operator__c = 'Equals',
				Value__c = 'Permission set assignment'
			),
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = operatorsRule.Id,
				ConditionNumber__c = 2,
				SourceField__c = 'Display',
				Operator__c = 'Contains',
				Value__c = 'Permission set'
			),
			new AuditTrailWatcherRuleCondition__c(
				AuditTrailWatcherRule__c = operatorsRule.Id,
				ConditionNumber__c = 3,
				SourceField__c = 'DelegateUser',
				Operator__c = 'isEmpty',
				Value__c = ''
			)
		};
	}

	@isTest
	static void testBatchExecutionWithMatchingAuditTrail() {
		Id ruleId = [SELECT Id FROM AuditTrailWatcherRule__c WHERE Name = 'PermSetAssign Rule' LIMIT 1].Id;
		String mockJson = buildMockAuditTrailJson('PermSetAssign', 'Permission set assignment', 'PermissionSet', 'delegate@example.com');
		List<SetupAuditTrail> mockRecords = (List<SetupAuditTrail>) JSON.deserialize(mockJson, Type.forName('List<SetupAuditTrail>'));

		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);
		batch.auditSelector = new MockAuditTrailSelector(mockRecords);

		// Direct invocation bypasses batch serialization; the mock selector would not survive
		// when Database.executeBatch serializes the batch for async execution.
		Iterable<SetupAuditTrail> iterable = batch.start(null);
		for (List<SetupAuditTrail> scope : chunk(iterable, 200)) {
			batch.execute(null, scope);
		}
		batch.finish(null);

		List<Event> activityEvents = [SELECT Id FROM Event WHERE WhatId = :ruleId AND Subject LIKE 'Audit Trail Alert:%'];
		System.assert(!activityEvents.isEmpty(), 'Activity event should have been created by TrackActivity.');
	}

	@isTest
	static void testNoChangesFound() {
		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);
		batch.auditSelector = new MockAuditTrailSelector(new List<SetupAuditTrail>());

		Iterable<SetupAuditTrail> iterable = batch.start(null);
		for (List<SetupAuditTrail> scope : chunk(iterable, 200)) {
			batch.execute(null, scope);
		}
		batch.finish(null);

		List<Event> activityEvents = [SELECT Id FROM Event WHERE Subject LIKE 'Audit Trail Alert:%'];
		System.assert(activityEvents.isEmpty(), 'No activity events should be created when no audit records match.');
	}

	@isTest
	static void testOrLogicMatch() {
		Id ruleId = [SELECT Id FROM AuditTrailWatcherRule__c WHERE Name = 'OR Rule' LIMIT 1].Id;
		String mockJson = buildMockAuditTrailJson('PermSetAssign', 'Permission set assignment', 'PermissionSet');
		List<SetupAuditTrail> mockRecords = (List<SetupAuditTrail>) JSON.deserialize(mockJson, Type.forName('List<SetupAuditTrail>'));

		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);
		batch.auditSelector = new MockAuditTrailSelector(mockRecords);

		Iterable<SetupAuditTrail> iterable = batch.start(null);
		for (List<SetupAuditTrail> scope : chunk(iterable, 200)) {
			batch.execute(null, scope);
		}
		batch.finish(null);

		List<Event> activityEvents = [SELECT Id FROM Event WHERE WhatId = :ruleId AND Subject LIKE 'Audit Trail Alert:%'];
		System.assert(!activityEvents.isEmpty(), 'OR rule should match when at least one condition matches.');
	}

	@isTest
	static void testOrLogicNoMatch() {
		Id ruleId = [SELECT Id FROM AuditTrailWatcherRule__c WHERE Name = 'OR Rule No Match' LIMIT 1].Id;
		String mockJson = buildMockAuditTrailJson('PermSetAssign', 'Permission set assignment', 'PermissionSet');
		List<SetupAuditTrail> mockRecords = (List<SetupAuditTrail>) JSON.deserialize(mockJson, Type.forName('List<SetupAuditTrail>'));

		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);
		batch.auditSelector = new MockAuditTrailSelector(mockRecords);

		Iterable<SetupAuditTrail> iterable = batch.start(null);
		for (List<SetupAuditTrail> scope : chunk(iterable, 200)) {
			batch.execute(null, scope);
		}
		batch.finish(null);

		List<Event> activityEvents = [SELECT Id FROM Event WHERE WhatId = :ruleId AND Subject LIKE 'Audit Trail Alert:%'];
		System.assert(activityEvents.isEmpty(), 'OR rule should not match when no conditions match.');
	}

	@isTest
	static void testCustomLogicMatch() {
		Id ruleId = [SELECT Id FROM AuditTrailWatcherRule__c WHERE Name = 'Custom Logic Rule' LIMIT 1].Id;
		String mockJson = buildMockAuditTrailJson('PermSetAssign', 'Permission set assignment', 'PermissionSet');
		List<SetupAuditTrail> mockRecords = (List<SetupAuditTrail>) JSON.deserialize(mockJson, Type.forName('List<SetupAuditTrail>'));

		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);
		batch.auditSelector = new MockAuditTrailSelector(mockRecords);

		Iterable<SetupAuditTrail> iterable = batch.start(null);
		for (List<SetupAuditTrail> scope : chunk(iterable, 200)) {
			batch.execute(null, scope);
		}
		batch.finish(null);

		List<Event> activityEvents = [SELECT Id FROM Event WHERE WhatId = :ruleId AND Subject LIKE 'Audit Trail Alert:%'];
		System.assert(!activityEvents.isEmpty(), 'Custom logic rule should match when formula (1 OR 2) evaluates to true.');
	}

	@isTest
	static void testEvaluateConditionOperators() {
		Id ruleId = [SELECT Id FROM AuditTrailWatcherRule__c WHERE Name = 'Operators Rule' LIMIT 1].Id;
		String mockJson = buildMockAuditTrailJson('PermSetAssign', 'Permission set assignment', 'PermissionSet');
		List<SetupAuditTrail> mockRecords = (List<SetupAuditTrail>) JSON.deserialize(mockJson, Type.forName('List<SetupAuditTrail>'));

		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);
		batch.auditSelector = new MockAuditTrailSelector(mockRecords);

		Iterable<SetupAuditTrail> iterable = batch.start(null);
		for (List<SetupAuditTrail> scope : chunk(iterable, 200)) {
			batch.execute(null, scope);
		}
		batch.finish(null);

		List<Event> activityEvents = [SELECT Id FROM Event WHERE WhatId = :ruleId AND Subject LIKE 'Audit Trail Alert:%'];
		System.assert(!activityEvents.isEmpty(), 'Operators rule should match when all conditions pass.');
	}

	private static List<List<SetupAuditTrail>> chunk(Iterable<SetupAuditTrail> iterable, Integer size) {
		List<List<SetupAuditTrail>> chunks = new List<List<SetupAuditTrail>>();
		List<SetupAuditTrail> current = new List<SetupAuditTrail>();
		for (SetupAuditTrail record : iterable) {
			current.add(record);
			if (current.size() == size) {
				chunks.add(current);
				current = new List<SetupAuditTrail>();
			}
		}
		if (!current.isEmpty()) {
			chunks.add(current);
		}
		return chunks;
	}

	@isTest
	static void testSchedulableExecution() {
		String jobId = System.schedule('Test AuditTrailWatcherBatch', '0 0 0 * * ?', new AuditTrailWatcherBatch());

		CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, NextFireTime FROM CronTrigger WHERE Id = :jobId];
		System.assertEquals('0 0 0 * * ?', ct.CronExpression, 'Cron expression should match.');
	}

	@isTest
	static void testCustomLogicEvaluator() {
		Map<Decimal, Boolean> results = new Map<Decimal, Boolean>();
		results.put(1, true);
		results.put(2, false);
		results.put(3, true);

		System.assertEquals(true, AuditTrailWatcherBatch.evaluateCustomLogic('1', results));
		System.assertEquals(false, AuditTrailWatcherBatch.evaluateCustomLogic('2', results));
		System.assertEquals(true, AuditTrailWatcherBatch.evaluateCustomLogic('1 AND 3', results));
		System.assertEquals(false, AuditTrailWatcherBatch.evaluateCustomLogic('1 AND 2', results));
		System.assertEquals(true, AuditTrailWatcherBatch.evaluateCustomLogic('1 OR 2', results));
		System.assertEquals(true, AuditTrailWatcherBatch.evaluateCustomLogic('(1 OR 2) AND 3', results));
	}
}
