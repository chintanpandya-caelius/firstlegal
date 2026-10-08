@isTest
private class TimezoneUtilityControllerTest {
    
    @isTest
    static void testAccountHandler() {
        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;
        Test.startTest();
        Map<String, String> result =
            TimezoneUtilityController.getTimezoneData(acc.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testContactHandler() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Contact con = new Contact(
            LastName = 'Test Contact',
            AccountId = acc.Id
        );
        insert con;

        Test.startTest();
        Map<String, String> result =
            TimezoneUtilityController.getTimezoneData(con.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testCaseHandler() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Contact con = new Contact(
            LastName = 'Test Contact',
            AccountId = acc.Id
        );
        insert con;

        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Origin = 'Phone',
            ContactId = con.Id,
            AccountId = acc.Id
        );
        insert c;

        Test.startTest();
        Map<String, String> result =
            TimezoneUtilityController.getTimezoneData(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testNullRecordId() {

        Test.startTest();
        Map<String, String> result =
            TimezoneUtilityController.getTimezoneData(null);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }
}