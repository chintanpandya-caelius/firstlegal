@IsTest
private class AccountFcpHandlerTest {

    @IsTest
    static void testFcpCustomerValid() {
        Account acc = new Account(
            Name = 'Valid FCP Account',
            Is_FCP_Customer__c = true,
            Client_Specific_Email__c = 'fcp@example.com',
            Assigned_POD__c = 'POD Alpha'
        );

        Test.startTest();
        AccountFcpHandler.runValidation(new List<Account>{ acc });
        Test.stopTest();
    }

    @IsTest
    static void testFcpCustomerInvalidMissingFields() {
        Account acc = new Account(
            Name = 'Invalid FCP Account',
            Is_FCP_Customer__c = true
        );

        Test.startTest();
        AccountFcpHandler.runValidation(new List<Account>{ acc });
        Test.stopTest();
    }

    @IsTest
    static void testNonFcpCustomerClearsFields() {
        Account acc = new Account(
            Name = 'Non FCP Account',
            Is_FCP_Customer__c = false,
            Client_Specific_Email__c = 'clearme@example.com',
            Assigned_POD__c = 'POD Beta'
        );

        Test.startTest();
        AccountFcpHandler.runValidation(new List<Account>{ acc });
        Test.stopTest();
    }

    @IsTest
    static void testBypassFlag() {
        AccountFcpHandler.bypassForTransaction = true;

        Account acc = new Account(
            Name = 'Bypassed Account',
            Is_FCP_Customer__c = true
        );

        Test.startTest();
        AccountFcpHandler.runValidation(new List<Account>{ acc });
        Test.stopTest();
    }
}