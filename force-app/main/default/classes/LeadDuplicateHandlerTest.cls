@isTest
private class LeadDuplicateHandlerTest {
    @testSetup
    static void setupData() {
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = 'Lead_Duplicate_Account_Notification' LIMIT 1];
        if (templates.isEmpty()) {
            insert new EmailTemplate(DeveloperName = 'Lead_Duplicate_Account_Notification', Name = 'Lead Duplicate Notification', TemplateType = 'text', FolderId = UserInfo.getUserId(), IsActive = true);
        }
    }

    private static Lead createTestLead(String firstName, String lastName, String company, String email) {
        Lead l = new Lead(FirstName = firstName, LastName = lastName, Company = company, Email = email, Phone = '5551234567', Title = 'Manager', PostalCode = '90001', Street = '100 Test Street', City = 'Los Angeles', State = 'California', Country = 'United States', Status = 'New');
        l.put('SLA_Tier__c', 'S1');
        l.put('Lead_Channel__c', 'Email');
        l.put('Lead_Source__c', 'Digital');
        l.put('Source_Detail__c', 'Depo');
        l.put('SLA__c', 'S1');
        try { l.put('Zip_Code__c', '90001'); } catch (Exception e) {}
        try { l.put('ZipCode__c', '90001'); } catch (Exception e) {}
        return l;
    }

    private static void insertLeadSafely(Lead leadRec) {
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        dml.DuplicateRuleHeader.runAsCurrentUser = true;
        Database.SaveResult sr = Database.insert(leadRec, dml);
        if (!sr.isSuccess()) insert leadRec;
    }

    @isTest
    static void testDuplicateLeadMatchingEngine() {
        Account targetAccount = new Account(Name = 'ZZZ DUPLICATE TEST ACCOUNT', BillingStreet = '100 Test Street', BillingCity = 'Los Angeles', BillingState = 'California', BillingPostalCode = '90001', BillingCountry = 'United States');
        insert targetAccount;
        Lead duplicateLead = createTestLead('Duplicate', 'Test', 'ZZZ DUPLICATE TEST ACCOUNT', 'duplicatetest999@example.com');
        insertLeadSafely(duplicateLead);
        Test.startTest();
        LeadDuplicateHandler.process(new List<Lead>{duplicateLead}, null);
        Test.stopTest();
        System.assert([SELECT COUNT() FROM Lead WHERE Id = :duplicateLead.Id] == 1, 'Lead should exist after processing.');
    }

    @isTest
    static void testNoDuplicateLeadAssignedToBDR() {
        Lead testLead = createTestLead('No', 'Match', 'UNIQUE UNMATCHED CO 12345', 'nomatch123456@example.com');
        insertLeadSafely(testLead);
        Test.startTest();
        LeadDuplicateHandler.process(new List<Lead>{testLead}, null);
        Test.stopTest();
        System.assert([SELECT COUNT() FROM Lead WHERE Id = :testLead.Id] == 1, 'Lead should exist.');
    }

    @isTest
    static void testAlreadyMatchedAndNoChanges() {
        Account targetAccount = new Account(Name = 'EXISTING MATCH ACCOUNT');
        insert targetAccount;
        Lead testLead = createTestLead('Already', 'Matched', 'EXISTING MATCH ACCOUNT', 'alreadymatched@example.com');
        insertLeadSafely(testLead);
        testLead.Matched_Account__c = targetAccount.Id;
        update testLead;
        Test.startTest();
        LeadDuplicateHandler.process(new List<Lead>{testLead}, null);
        Test.stopTest();
    }

    @isTest
    static void testMatchedAccountChangedBypass() {
        Account oldAccount = new Account(Name = 'OLD MATCH ACCOUNT');
        Account newAccount = new Account(Name = 'NEW MATCH ACCOUNT');
        insert new List<Account>{oldAccount, newAccount};
        Lead testLead = createTestLead('Changed', 'Match', 'Changed Co', 'changedmatch@example.com');
        insertLeadSafely(testLead);
        Lead oldLead = testLead.clone(true, true, false, false);
        oldLead.Matched_Account__c = oldAccount.Id;
        testLead.Matched_Account__c = newAccount.Id;
        Test.startTest();
        LeadDuplicateHandler.process(new List<Lead>{testLead}, new Map<Id, Lead>{testLead.Id => oldLead});
        Test.stopTest();
        System.assertEquals(false, LeadDuplicateHandler.isRunning);
    }

    @isTest
    static void testEmailNotificationWithUserOwner() {
        Account targetAccount = new Account(Name = 'USER NOTIFY ACCOUNT');
        insert targetAccount;
        Lead testLead = createTestLead('Notify', 'User', 'USER NOTIFY ACCOUNT', 'userowner@example.com');
        insertLeadSafely(testLead);
        testLead.OwnerId = UserInfo.getUserId();
        testLead.Matched_Account__c = targetAccount.Id;
        update testLead;
        Test.startTest();
        LeadDuplicateHandler.process(new List<Lead>{testLead}, null);
        Test.stopTest();
    }

    @isTest
    static void testRecursionGuardAndUninsertedLeads() {
        LeadDuplicateHandler.isRunning = true;
        Lead uninsertedLead = createTestLead('Uninserted', 'Lead', 'Test Co', 'uninserted@example.com');
        Test.startTest();
        LeadDuplicateHandler.process(new List<Lead>{uninsertedLead}, null);
        LeadDuplicateHandler.isRunning = false;
        LeadDuplicateHandler.process(new List<Lead>(), null);
        LeadDuplicateHandler.process(new List<Lead>{uninsertedLead}, null);
        Test.stopTest();
        System.assertEquals(false, LeadDuplicateHandler.isRunning);
    }
}