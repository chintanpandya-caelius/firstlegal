public with sharing class TicketExportController {
    private static final List<ExportField> EXPORTABLE_FIELDS = new List<ExportField>{
        new ExportField('Ticket Number', 'CaseNumber', true),
        new ExportField('Status', 'Status', false),
        new ExportField('Opened', 'CreatedDate', false),
        new ExportField('Ticket type', 'Type', false),
		new ExportField('Sub type', 'Ticket_SubType__c', false),
        new ExportField('Matter Number', 'Matter_Number__c', false),
        new ExportField('Case Number', 'Court_Case_Number__c', false),
        new ExportField('Created By', 'CreatedBy.Name', false),
        new ExportField('Priority', 'Priority', false),
        new ExportField('Due Date', 'Due_Date__c', false),
		new ExportField('Description', 'Description', false)
    };

    public class ExportField {
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public Boolean defaultSelected;
        public ExportField(String label, String apiName, Boolean defaultSelected) {
            this.label = label;
            this.apiName = apiName;
            this.defaultSelected = defaultSelected;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ExportField> getExportFieldMetadata() {
        return EXPORTABLE_FIELDS;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getTicketExportData(
        List<Id> ticketIds,
        List<String> fieldApiNames
    ) {
        // No selection -> header-only file is built entirely client-side,
        // so we never even need to hit this method for that case. Still,
        // guard it defensively.
        if (ticketIds == null || ticketIds.isEmpty()
            || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        if (!Schema.sObjectType.Case.isAccessible()) {
            throw new AuraHandledException('Insufficient access to Case records.');
        }

        // Whitelist check — never trust field names coming from the client.
        Set<String> allowed = new Set<String>();
        for (ExportField ef : EXPORTABLE_FIELDS) {
            allowed.add(ef.apiName);
        }
        List<String> safeFields = new List<String>();
        for (String f : fieldApiNames) {
            if (allowed.contains(f)) {
                safeFields.add(f);
            }
        }
        if (safeFields.isEmpty()) {
            return new List<Map<String, Object>>();
        }

        String query = 'SELECT Id, ' + String.join(safeFields, ', ')
            + ' FROM Case WHERE Id IN :ticketIds';
        List<Case> records = Database.query(query);

        // Enforce FLS on whatever the running user is allowed to see.
        SObjectAccessDecision decision =
            Security.stripInaccessible(AccessType.READABLE, records);
        List<Case> safeRecords = (List<Case>) decision.getRecords();

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Case c : safeRecords) {
            Map<String, Object> row = new Map<String, Object>();
            for (String field : safeFields) {
                row.put(field, resolveFieldValue(c, field));
            }
            rows.add(row);
        }
        return rows;
    }

    // Resolves dotted relationship paths e.g. Contact.Name, Owner.Name
    private static Object resolveFieldValue(SObject record, String fieldPath) {
        List<String> parts = fieldPath.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (current == null) {
                return null;
            }
            current = current.getSObject(parts[i]);
        }
        return current == null ? null : current.get(parts[parts.size() - 1]);
    }
}