/**
 * Selector for SetupAuditTrail records.
 * This class exists to allow mocking of read-only SetupAuditTrail objects in unit tests,
 * since SetupAuditTrail cannot be created via DML and test orgs may not have predictable audit data.
 */
public virtual class AuditTrailSelector {

	public virtual Iterable<SetupAuditTrail> getAuditTrailIterable(DateTime lastRunDate, Set<String> actions, Set<String> fieldsToQuery) {
		String query = buildQuery(lastRunDate, actions, fieldsToQuery);
		return (List<SetupAuditTrail>) Database.query(query);
	}

	private String buildQuery(DateTime lastRunDate, Set<String> actions, Set<String> fieldsToQuery) {
		Set<String> selectFields = new Set<String>{
			'Id', 'Action', 'Display', 'CreatedDate', 'CreatedById', 'CreatedBy.Username', 'Section', 'DelegateUser'
		};
		if (fieldsToQuery != null) {
			selectFields.addAll(fieldsToQuery);
		}
		String query = 'SELECT ' + String.join(new List<String>(selectFields), ', ') +
			' FROM SetupAuditTrail';

		if (lastRunDate != null) {
			query += ' WHERE CreatedDate > :lastRunDate';
		}

		if (actions != null && !actions.isEmpty()) {
			query += (lastRunDate != null ? ' AND' : ' WHERE') + ' Action IN :actions';
		}
		query += ' ORDER BY Action, CreatedDate';
		return query;
	}
}
