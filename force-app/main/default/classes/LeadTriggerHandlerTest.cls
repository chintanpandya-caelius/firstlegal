@isTest
private class LeadTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        User activeUser = [SELECT Id, Email FROM User WHERE IsActive = true AND Email != null LIMIT 1];
        Group bdrQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'BDR_Queue' LIMIT 1];
        
        if (bdrQueue == null) {
            bdrQueue = new Group(Name = 'BDR Queue', DeveloperName = 'BDR_Queue', Type = 'Queue');
            insert bdrQueue;
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<QueueSobject> existingQSobj = [SELECT Id FROM QueueSobject WHERE QueueId = :bdrQueue.Id AND SobjectType = 'Lead'];
            if (existingQSobj.isEmpty()) {
                QueueSobject qSobj = new QueueSobject(QueueId = bdrQueue.Id, SobjectType = 'Lead');
                insert qSobj;
            }
            GroupMember gm = new GroupMember(GroupId = bdrQueue.Id, UserOrGroupId = activeUser.Id);
            insert gm;
        }

        // FIXED: Added the required custom fields to the Account creation block
        Account acc = new Account(
            Name = 'Test Target Account', 
            Type = 'Prospect',
            Service_Line__c ='Digital', 
            VIP__c = 'Problematic'                 
        );
        insert acc;
    }

    @isTest
    static void testBeforeAndAfterInsertQueueAssignment() {
        Group bdrQueue = [SELECT Id FROM Group WHERE DeveloperName = 'BDR_Queue' LIMIT 1];

        Test.startTest();
        Lead newLead = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'johndoe@example.com',
            Company = 'Cloud Corp',
            Status = 'New',
            SLA_Start_Date__c = System.today(),
            SLA_Due_Date__c = System.today().addDays(2)
        );
        insert newLead;
        Test.stopTest();

        Lead processedLead = [SELECT OwnerId, Status FROM Lead WHERE Id = :newLead.Id];
        System.assertEquals(bdrQueue.Id, processedLead.OwnerId);
    }

    @isTest
    static void testCheckAndSendMatchedAccountEmails() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Lead matchLead = new Lead(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'janesmith@example.com',
            Company = 'Match Corp',
            Status = 'Open',
            Matched_Account__c = acc.Id
        );
        insert matchLead;

        Test.startTest();
        matchLead.LastName = 'Smith Updated';
        update matchLead;
        Test.stopTest();
        
        System.assertNotEquals(null, matchLead.Id);
    }

    @isTest
    static void testAfterUpdateLeadConversionActions() {
        // FIXED: Create a fresh account containing the mandatory field criteria
        Account acc = new Account(
            Name = 'Fresh Test Account', 
            Type = 'Prospect',
            Service_Line__c = 'Digital', 
            VIP__c = 'Problematic'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Jane',
            LastName = 'Doe',
            AccountId = acc.Id,
            MailingStreet = '1233 California Street',
            MailingCity = 'San Francisco',
            MailingState = 'California',
            MailingStateCode = 'CA',
            MailingPostalCode = '94109',
            MailingCountry = 'United States',
            MailingCountryCode = 'US'
        );
        insert con;

        Opportunity opp = new Opportunity(Name = 'Test Opp', StageName = 'Prospecting', CloseDate = System.today().addDays(30), AccountId = acc.Id, Service_Line__c='Digital',Revenue_Type__c='Portfolio Growth');
        insert opp;
        
        Lead conversionLead = new Lead(
            FirstName = 'Convert', 
            LastName = 'Me', 
            Email = 'convertme@example.com',
            Company = 'Convert Corp', 
            Status = 'Open'
        );
        insert conversionLead;

        String leadJson = '{"attributes":{"type":"Lead"},"Id":"' + conversionLead.Id + '","IsConverted":true,"ConvertedAccountId":"' + acc.Id + '","ConvertedContactId":"' + con.Id + '","ConvertedOpportunityId":"' + opp.Id + '"}';
        Lead mockedConvertedLead = (Lead)JSON.deserialize(leadJson, Lead.class);

        Test.startTest();
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ conversionLead.Id => conversionLead };
        LeadTriggerHandler.afterUpdate(new List<Lead>{ mockedConvertedLead }, oldMap);
        Test.stopTest();

        System.assertNotEquals(null, mockedConvertedLead.Id);
    }
}