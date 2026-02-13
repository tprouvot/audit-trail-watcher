trigger AuditTrailWatcherRuleTrigger on AuditTrailWatcherRule__c (before insert, before update) {
	if (Trigger.isBefore) {
		AuditTrailWatcherRuleTriggerHandler.validateCustomLogic(Trigger.new);
	}
}
