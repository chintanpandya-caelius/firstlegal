@isTest
private class CaseEmailDefaultHandlerTest {
    private static Account createAccount(String name, Id parentId, Boolean isFCP, String clientEmail) {
        Account a = new Account(
            Name = name,
            ParentId = parentId,
            Is_FCP_Customer__c = isFCP,
            Client_Specific_Email__c = clientEmail
        );
        Database.insert(a, AccessLevel.SYSTEM_MODE);
        return a;
    }
    @isTest
    static void testFCPAccount_UsesClientSpecificEmail() {
        Account root = createAccount('Root FCP', null, true, 'fcp-client@example.com');
        Case c = new Case(AccountId = root.Id, Subject = 'Test FCP');
        Database.insert(c, AccessLevel.SYSTEM_MODE);
        
        List<QuickAction.QuickActionDefaults> defaultsList = new List<QuickAction.QuickActionDefaults>{
            Test.newSendEmailQuickActionDefaults(c.Id, null)
        };
        Test.startTest();
        CaseEmailDefaultHandler ch = new CaseEmailDefaultHandler();
        ch.onInitDefaults(defaultsList);
        Test.stopTest();
    }
}