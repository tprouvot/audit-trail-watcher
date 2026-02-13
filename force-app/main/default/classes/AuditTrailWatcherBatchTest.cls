@isTest
private class AuditTrailWatcherBatchTest {

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
	}

	@isTest
	static void testBatchExecution() {
		Id ruleId = [SELECT Id FROM AuditTrailWatcherRule__c WHERE Name = 'PermSetAssign Rule' LIMIT 1].Id;
		AuditTrailWatcherBatch batch = new AuditTrailWatcherBatch(1);

		Test.startTest();
		Database.executeBatch(batch);
		Test.stopTest();

		List<Event> activityEvents = [SELECT Id FROM Event WHERE WhatId = :ruleId AND Subject LIKE 'Audit Trail Alert:%'];
		System.assert(!activityEvents.isEmpty(), 'Activity event should have been created by TrackActivity.');
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
