@IsTest
private class TicketExportControllerTest {

    @TestSetup
    static void createTestData() {
        Account acc = new Account(
            Name = 'Ticket Export Test Account'
        );
        insert acc;

        Case ticket = new Case(
            AccountId = acc.Id,
            Subject = 'Ticket Export Test Case',
            Status = getFirstPicklistValue(Case.Status),
            Origin = getFirstPicklistValue(Case.Origin),
            Priority = getFirstPicklistValue(Case.Priority),
            Due_Date__c = Date.today().addDays(7),
            Matter_Number__c = 'MAT-TEST-001',
            Court_Case_Number__c = 'COURT-TEST-001',
            Description = 'Description for ticket export test'
        );

        insert ticket;
    }


    // ------------------------------------------------------------
    // Test metadata
    // ------------------------------------------------------------
    @IsTest
    static void testGetExportFieldMetadata() {
        Test.startTest();

        List<TicketExportController.ExportField> fields =
            TicketExportController.getExportFieldMetadata();

        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assertEquals(11, fields.size());

        System.assertEquals(
            'Ticket Number',
            fields[0].label
        );
        System.assertEquals(
            'CaseNumber',
            fields[0].apiName
        );
        System.assertEquals(
            true,
            fields[0].defaultSelected
        );

        System.assertEquals(
            'Status',
            fields[1].label
        );
        System.assertEquals(
            'Status',
            fields[1].apiName
        );
        System.assertEquals(
            false,
            fields[1].defaultSelected
        );

        // Verify the relationship field is exposed correctly.
        TicketExportController.ExportField createdByField =
            fields[7];

        System.assertEquals(
            'Created By',
            createdByField.label
        );
        System.assertEquals(
            'CreatedBy.Name',
            createdByField.apiName
        );
    }


    // ------------------------------------------------------------
    // Defensive/empty input tests
    // ------------------------------------------------------------
    @IsTest
    static void testGetTicketExportData_NullInputs() {
        Test.startTest();

        List<Map<String, Object>> result1 =
            TicketExportController.getTicketExportData(
                null,
                null
            );

        List<Map<String, Object>> result2 =
            TicketExportController.getTicketExportData(
                new List<Id>(),
                new List<String>()
            );

        List<Map<String, Object>> result3 =
            TicketExportController.getTicketExportData(
                new List<Id>(),
                new List<String>{ 'CaseNumber' }
            );

        List<Map<String, Object>> result4 =
            TicketExportController.getTicketExportData(
                new List<Id>(),
                null
            );

        List<Map<String, Object>> result5 =
            TicketExportController.getTicketExportData(
                new List<Id>{ getTestCase().Id },
                null
            );

        Test.stopTest();

        System.assertEquals(0, result1.size());
        System.assertEquals(0, result2.size());
        System.assertEquals(0, result3.size());
        System.assertEquals(0, result4.size());
        System.assertEquals(0, result5.size());
    }


    // ------------------------------------------------------------
    // Invalid whitelist input
    // ------------------------------------------------------------
    @IsTest
    static void testGetTicketExportData_InvalidFields() {
        Case ticket = getTestCase();

        Test.startTest();

        List<Map<String, Object>> result =
            TicketExportController.getTicketExportData(
                new List<Id>{ ticket.Id },
                new List<String>{
                    'NotARealField',
                    'Some_Unsafe_Field__c'
                }
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(
            0,
            result.size(),
            'No rows should be returned when every requested field is rejected by the whitelist.'
        );
    }


    // ------------------------------------------------------------
    // Valid export + whitelist filtering + relationship resolution
    // ------------------------------------------------------------
    @IsTest
    static void testGetTicketExportData_ValidFields() {
        Case ticket = getTestCase();

        List<String> requestedFields = new List<String>{
            'CaseNumber',
            'Status',
            'CreatedDate',
            'Type',
            'Ticket_SubType__c',
            'Matter_Number__c',
            'Court_Case_Number__c',
            'CreatedBy.Name',
            'Priority',
            'Due_Date__c',
            'Description',

            // Should be ignored by whitelist.
            'Id',
            'Name',
            'Definitely_Not_Allowed__c'
        };

        Test.startTest();

        List<Map<String, Object>> rows =
            TicketExportController.getTicketExportData(
                new List<Id>{ ticket.Id },
                requestedFields
            );

        Test.stopTest();

        System.assertEquals(1, rows.size());

        Map<String, Object> row = rows[0];

        // Whitelisted fields should be present.
        System.assert(row.containsKey('CaseNumber'));
        System.assert(row.containsKey('Status'));
        System.assert(row.containsKey('CreatedDate'));
        System.assert(row.containsKey('Type'));
        System.assert(row.containsKey('Ticket_SubType__c'));
        System.assert(row.containsKey('Matter_Number__c'));
        System.assert(row.containsKey('Court_Case_Number__c'));
        System.assert(row.containsKey('CreatedBy.Name'));
        System.assert(row.containsKey('Priority'));
        System.assert(row.containsKey('Due_Date__c'));
        System.assert(row.containsKey('Description'));

        // Non-whitelisted fields must not appear.
        System.assertEquals(false, row.containsKey('Id'));
        System.assertEquals(false, row.containsKey('Name'));
        System.assertEquals(
            false,
            row.containsKey('Definitely_Not_Allowed__c')
        );

        // Verify representative values.
        System.assertEquals(
            ticket.CaseNumber,
            (String) row.get('CaseNumber')
        );

        System.assertEquals(
            ticket.Status,
            (String) row.get('Status')
        );

        System.assertEquals(
            ticket.Matter_Number__c,
            (String) row.get('Matter_Number__c')
        );

        System.assertEquals(
            ticket.Court_Case_Number__c,
            (String) row.get('Court_Case_Number__c')
        );

        System.assertEquals(
            ticket.Priority,
            (String) row.get('Priority')
        );

        System.assertEquals(
            ticket.Description,
            (String) row.get('Description')
        );

        // This specifically exercises resolveFieldValue()
        // with the CreatedBy.Name relationship path.
        System.assertEquals(
            UserInfo.getName(),
            (String) row.get('CreatedBy.Name')
        );
    }


    // ------------------------------------------------------------
    // Valid IDs but no matching records
    // ------------------------------------------------------------
    @IsTest
    static void testGetTicketExportData_NoMatchingRecords() {
        Case ticket = getTestCase();

        delete ticket;

        Test.startTest();

        List<Map<String, Object>> result =
            TicketExportController.getTicketExportData(
                new List<Id>{ ticket.Id },
                new List<String>{ 'CaseNumber', 'Status' }
            );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }


    // ------------------------------------------------------------
    // Mixed valid + invalid field selection
    // ------------------------------------------------------------
    @IsTest
    static void testGetTicketExportData_MixedFields() {
        Case ticket = getTestCase();

        Test.startTest();

        List<Map<String, Object>> result =
            TicketExportController.getTicketExportData(
                new List<Id>{ ticket.Id },
                new List<String>{
                    'CaseNumber',
                    'NotAllowed__c',
                    'CreatedBy.Name',
                    'AnotherFakeField__c'
                }
            );

        Test.stopTest();

        System.assertEquals(1, result.size());

        Map<String, Object> row = result[0];

        System.assert(row.containsKey('CaseNumber'));
        System.assert(row.containsKey('CreatedBy.Name'));

        System.assertEquals(
            false,
            row.containsKey('NotAllowed__c')
        );

        System.assertEquals(
            false,
            row.containsKey('AnotherFakeField__c')
        );
    }


    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    private static Case getTestCase() {
        return [
            SELECT
                Id,
                CaseNumber,
                Status,
                CreatedDate,
                Type,
                Ticket_SubType__c,
                Matter_Number__c,
                Court_Case_Number__c,
                CreatedBy.Name,
                Priority,
                Due_Date__c,
                Description
            FROM Case
            WHERE Subject = 'Ticket Export Test Case'
            LIMIT 1
        ];
    }


    private static String getFirstPicklistValue(
        Schema.SObjectField field
    ) {
        for (Schema.PicklistEntry entry :
             field.getDescribe().getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }
}