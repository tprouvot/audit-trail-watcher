@isTest
private class AuditTrailWatcherBatchTest {

	@TestSetup
	static void setup() {
		// Create test users
		Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User'];
		String uniqueId = String.valueOf(Crypto.getRandomLong());

		User testUser1 = new User(
			Alias = 'tuser1',
			Email = 'testuser1@example.com',
			EmailEncodingKey = 'UTF-8',
			LastName = 'Testing',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			ProfileId = p.Id,
			TimeZoneSidKey = 'America/Los_Angeles',
			UserName = 'testuser1_' + uniqueId + '@example.com.test'
		);
		insert testUser1;

		EmailTemplate template = new EmailTemplate(
				Name = 'AuditTrailWatcherNotification',
				DeveloperName = 'AuditTrailWatcherNotification',
				FolderId = UserInfo.getUserId(),
				IsActive = true,
				Subject = 'Audit Trail Alert: {!AuditTrailWatcherRule__c.Name}',
				Body = 'Test email body',
				HtmlValue = '<p>Test email body</p><p>{TableContent}</p>',
				TemplateType = 'custom'
			);
			insert template;

		PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'AuditTrailWatcherAdmin'];
		insert new PermissionSetAssignment(AssigneeId = testUser1.Id, PermissionSetId = ps.Id);

		System.runas(testUser1) {
			List<AuditTrailWatcherRule__c> rules = new List<AuditTrailWatcherRule__c>{
				new AuditTrailWatcherRule__c(
				Name = 'Test Rule 1',
				Action__c = 'deactivateduser',
				NotificationRecipient__c = testUser1.Id,
				IsActive__c = true,
				SendPlatformEvent__c = true,
				Severity__c = 'Critical'
			),
			new AuditTrailWatcherRule__c(
				Name = 'Test Rule 2',
				Action__c = 'PermSetGroupAssign',
				NotificationRecipient__c = testUser1.Id,
				IsActive__c = true,
				SendPlatformEvent__c = false,
				Severity__c = 'Warning'
			)};
			insert rules;
		}
	}

	@isTest
	static void testBatchScenarios() {
		// Get test user
		User testUser = [SELECT Id FROM User WHERE Alias = 'tuser1' LIMIT 1];

		Test.startTest();

		// Scenario 1: Test with active rules and create audit trail
		System.runAs(new User(Id = UserInfo.getUserId())) {
			testUser.IsActive = false;
			update testUser;
		}

		// Verify that a SetupAuditTrail record was created
		List<SetupAuditTrail> auditTrails = [ SELECT Id, Action FROM SetupAuditTrail];
		System.assert(!auditTrails.isEmpty(), 'Should have created a SetupAuditTrail record');


		Database.executeBatch(new AuditTrailWatcherBatch());
		Test.stopTest();

		// Verify emails were sent
		Integer emailInvocations = Limits.getEmailInvocations();
		System.assert(emailInvocations > 0, 'Should have sent emails');
	}
}