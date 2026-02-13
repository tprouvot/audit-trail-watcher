@isTest
private class AuditTrailWatcherRuleTriggerHandlerTest {

	@testSetup
	static void setup() {
		insert new AuditTrailWatcherRule__c(
			Name = 'Test Rule',
			LogicType__c = 'AND',
			IsActive__c = true
		);
	}

	@isTest
	static void testCustomLogicRequiresCustomLogic() {
		AuditTrailWatcherRule__c rule = [SELECT Id FROM AuditTrailWatcherRule__c LIMIT 1];
		rule.LogicType__c = 'Custom';
		rule.CustomLogic__c = null;

		try {
			update rule;
			System.assert(false, 'Should have failed validation');
		} catch (DmlException e) {
			System.assert(e.getMessage().contains('Custom Logic'), 'Should fail on missing Custom Logic');
		}
	}

	@isTest
	static void testCustomLogicValidFormula() {
		AuditTrailWatcherRule__c rule = [SELECT Id FROM AuditTrailWatcherRule__c LIMIT 1];
		rule.LogicType__c = 'Custom';
		rule.CustomLogic__c = '(1 OR 2) AND 1';

		update rule;

		rule = [SELECT LogicType__c, CustomLogic__c FROM AuditTrailWatcherRule__c WHERE Id = :rule.Id];
		System.assertEquals('Custom', rule.LogicType__c);
		System.assertEquals('(1 OR 2) AND 1', rule.CustomLogic__c);
	}

	@isTest
	static void testCustomLogicUnbalancedParentheses() {
		AuditTrailWatcherRule__c rule = [SELECT Id FROM AuditTrailWatcherRule__c LIMIT 1];
		rule.LogicType__c = 'Custom';
		rule.CustomLogic__c = '(1 OR 2';

		try {
			update rule;
			System.assert(false, 'Should have failed - unbalanced parentheses');
		} catch (DmlException e) {
			System.assert(e.getMessage().contains('parentheses'), 'Should fail on unbalanced parentheses');
		}
	}
}
