/**
 * Handler for AuditTrailWatcherRule__c triggers.
 * Validates custom logic formula syntax when LogicType is Custom.
 */
public with sharing class AuditTrailWatcherRuleTriggerHandler {

	public static void validateCustomLogic(List<AuditTrailWatcherRule__c> rules) {
		for (AuditTrailWatcherRule__c rule : rules) {
			if (rule.LogicType__c != 'Custom' || String.isBlank(rule.CustomLogic__c)) {
				continue;
			}

			String error = validateCustomLogicFormula(rule.CustomLogic__c);
			if (error != null) {
				rule.addError(error);
			}
		}
	}

	@TestVisible
	private static String validateCustomLogicFormula(String formula) {
		if (String.isBlank(formula)) {
			return 'Custom Logic cannot be empty.';
		}

		String trimmed = formula.trim();
		if (extractConditionNumbers(trimmed).isEmpty()) {
			return 'Custom Logic must reference at least one condition number (e.g., 1, 2, 3).';
		}

		if (!hasBalancedParentheses(trimmed)) {
			return 'Custom Logic has unbalanced parentheses.';
		}

		if (!isValidSyntax(trimmed)) {
			return 'Custom Logic has invalid syntax. Use only condition numbers, AND, OR, and parentheses. Example: (1 OR 2) AND 3';
		}

		return null;
	}

	private static Set<Decimal> extractConditionNumbers(String formula) {
		Set<Decimal> numbers = new Set<Decimal>();
		Matcher m = Pattern.compile('\\d+').matcher(formula);
		while (m.find()) {
			numbers.add(Decimal.valueOf(m.group()));
		}
		return numbers;
	}

	private static Boolean hasBalancedParentheses(String formula) {
		Integer count = 0;
		for (Integer i = 0; i < formula.length(); i++) {
			String c = formula.substring(i, i + 1);
			if (c == '(') count++;
			else if (c == ')') {
				count--;
				if (count < 0) return false;
			}
		}
		return count == 0;
	}

	private static Boolean isValidSyntax(String formula) {
		String normalized = formula.toUpperCase().replaceAll('\\s+', ' ')
			.replace('(', ' ( ').replace(')', ' ) ').trim();
		Set<String> validTokens = new Set<String>{ 'AND', 'OR' };

		for (String token : normalized.split('\\s+')) {
			if (token == '(' || token == ')' || token.isNumeric() || validTokens.contains(token)) continue;
			return false;
		}
		return true;
	}
}
