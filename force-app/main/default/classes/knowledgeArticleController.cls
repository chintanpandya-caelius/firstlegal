public with sharing class knowledgeArticleController {

    public class FieldData {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Integer sortOrder;
    }

    private static final String FIELD_SET_NAME  = 'Knowledge_Portal_Fields';
    private static final String KNOWLEDGE_OBJECT = 'Knowledge__kav';

    private static final Set<String> RICH_TEXT_TYPES = new Set<String>{
        'TEXTAREA'
    };

    @AuraEnabled(cacheable=true)
    public static List<FieldData> getArticleFields(String recordId) {

        if (String.isBlank(recordId)) {
            return new List<FieldData>();
        }

        Map<String, Schema.FieldSet> fieldSetMap =
            Schema.SObjectType.Knowledge__kav.fieldSets.getMap();

        if (!fieldSetMap.containsKey(FIELD_SET_NAME)) {
            throw new AuraHandledException(
                'Field Set "' + FIELD_SET_NAME + '" not found on ' +
                KNOWLEDGE_OBJECT + '. Please create it in Object Manager.'
            );
        }

        Schema.FieldSet fs = fieldSetMap.get(FIELD_SET_NAME);
        List<Schema.FieldSetMember> members = fs.getFields();

        if (members == null || members.isEmpty()) {
            return new List<FieldData>();
        }

        List<String> apiNames    = new List<String>();
        Map<String, String>  labelMap = new Map<String, String>();
        Map<String, String>  typeMap  = new Map<String, String>();
        Map<String, Integer> orderMap = new Map<String, Integer>();

        Integer idx = 0;

        for (Schema.FieldSetMember m : members) {
            String fn = m.getFieldPath();

            apiNames.add(fn);
            labelMap.put(fn, m.getLabel());
            orderMap.put(fn, idx++);

            String displayType = String.valueOf(m.getType()).toUpperCase();

            if (RICH_TEXT_TYPES.contains(displayType)) {
                Schema.DescribeFieldResult dfr =
                    Schema.SObjectType.Knowledge__kav.fields.getMap()
                        .get(fn)?.getDescribe();

                typeMap.put(fn,
                    (dfr != null && dfr.isHtmlFormatted())
                        ? 'RICHTEXT'
                        : 'TEXT'
                );
            } else if (displayType == 'URL') {
                typeMap.put(fn, 'URL');
            } else if (displayType == 'DATE' || displayType == 'DATETIME') {
                typeMap.put(fn, 'DATE');
            } else if (displayType == 'BOOLEAN') {
                typeMap.put(fn, 'BOOLEAN');
            } else {
                typeMap.put(fn, 'TEXT');
            }
        }

        String soql =
            'SELECT ' + String.join(apiNames, ', ') +
            ' FROM Knowledge__kav' +
            ' WHERE Id = :recordId' +
            ' AND PublishStatus = \'Online\'' +
            ' WITH USER_MODE' +
            ' LIMIT 1';

        List<SObject> rows = Database.query(soql);

        if (rows.isEmpty()) {
            return new List<FieldData>();
        }

        SObject article = rows[0];
        List<FieldData> result = new List<FieldData>();

        for (String fn : apiNames) {

            Object rawValue = article.get(fn);
            if (rawValue == null) continue;

            String strValue = String.valueOf(rawValue);
            if (String.isBlank(strValue)) continue;

            if (typeMap.get(fn) == 'BOOLEAN' && strValue == 'false') continue;

            FieldData fd  = new FieldData();
            fd.label      = labelMap.get(fn);
            fd.value      = strValue;
            fd.fieldType  = typeMap.get(fn);
            fd.sortOrder  = orderMap.get(fn);

            result.add(fd);
        }

        return result;
    }
}