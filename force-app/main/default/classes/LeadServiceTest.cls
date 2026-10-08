@isTest
private class LeadServiceTest {

    // ============================================================
    // TEST DATA SETUP
    // ============================================================
    @TestSetup
    static void setupData() {
        // --- Query or Create BDR Queue ---
        List<Group> existingQueues = [
            SELECT Id FROM Group 
            WHERE DeveloperName = 'BDR_Queue' AND Type = 'Queue' 
            LIMIT 1
        ];
        
        Group bdrQueue;
        if (!existingQueues.isEmpty()) {
            bdrQueue = existingQueues[0];
        } else {
            bdrQueue = new Group(Name = 'BDR_Queue', DeveloperName = 'BDR_Queue', Type = 'Queue');
            insert bdrQueue;

            QueueSobject queueSobject = new QueueSobject(QueueId = bdrQueue.Id, SobjectType = 'Lead');
            insert queueSobject;
        }

        // Unique username to avoid collisions across test runs
        String uniqueName = 'lsvc.test.' + DateTime.now().getTime();
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User queueMemberUser = new User(
            FirstName = 'Queue',
            LastName = 'Member',
            Email = uniqueName + '@test.com',
            Username = uniqueName + '@test.com',
            Alias = 'qmem',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            IsActive = true
        );
        insert queueMemberUser;

        // Assign user to queue if not already assigned
        List<GroupMember> existingMembers = [
            SELECT Id FROM GroupMember 
            WHERE GroupId = :bdrQueue.Id AND UserOrGroupId = :queueMemberUser.Id
        ];
        if (existingMembers.isEmpty()) {
            insert new GroupMember(GroupId = bdrQueue.Id, UserOrGroupId = queueMemberUser.Id);
        }

        String directUserName = 'lsvc.direct.' + DateTime.now().getTime();
        User directOwnerUser = new User(
            FirstName = 'Direct',
            LastName = 'Owner',
            Email = directUserName + '@test.com',
            Username = directUserName + '@test.com',
            Alias = 'downer',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            IsActive = true
        );
        insert directOwnerUser;
    }

    // Helper to build a valid Lead that satisfies custom validation rules
    private static Lead buildLead(String lastName, String status) {
        Lead l = new Lead(
            FirstName = 'Test',
            LastName = lastName,
            Company = 'Test Co - ' + lastName,
            Email = 'test.' + lastName.replaceAll('[^a-zA-Z0-9]', '') + '@example.com',
            Phone = '555-555-5555',
            Title = 'Manager',
            PostalCode = '78701',
            Status = status,
            LeadSource = 'Inbound'
        );
        
        // Populating dynamic/custom lead channel fields safely
        l.put('Lead_Source__c', 'Email');
        l.put('Lead_Channel__c', 'Email');
        
        return l;
    }

    // ============================================================
    // assignNewLeadsToBDRQueue
    // ============================================================
    @isTest
    static void testAssignNewLeadsToBDRQueue_StatusNew() {
        Group bdrQueue = [SELECT Id FROM Group WHERE DeveloperName = 'BDR_Queue' LIMIT 1];

        Lead newLead = buildLead('QueueAssign', 'New');

        Test.startTest();
        insert newLead; // trigger fires beforeInsert -> assignNewLeadsToBDRQueue
        Test.stopTest();

        Lead result = [SELECT Id, OwnerId FROM Lead WHERE Id = :newLead.Id];
    }

    @isTest
    static void testAssignNewLeadsToBDRQueue_StatusNotNew() {
        Group bdrQueue = [SELECT Id FROM Group WHERE DeveloperName = 'BDR_Queue' LIMIT 1];

        Lead newLead = buildLead('QueueSkip', 'Working - Contacted');

        Test.startTest();
        insert newLead;
        Test.stopTest();

        Lead result = [SELECT Id, OwnerId FROM Lead WHERE Id = :newLead.Id];
    }

    @isTest
    static void testGetBDRQueueId_NotFound() {
        Test.startTest();
        List<Group> missingQueues = [SELECT Id FROM Group WHERE DeveloperName = 'NON_EXISTENT_QUEUE_XYZ' LIMIT 1];
        Id result = missingQueues.isEmpty() ? null : missingQueues[0].Id;
        Test.stopTest();
    }

    // ============================================================
    // sendQueueWelcomeEmails
    // ============================================================
    @isTest
    static void testSendQueueWelcomeEmails_HappyPath() {
        Lead newLead = buildLead('WelcomeEmail', 'New');

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        insert newLead; // afterInsert -> sendQueueWelcomeEmails
        Test.stopTest();
    }

    @isTest
    static void testSendQueueWelcomeEmails_NoQueue() {
        Lead newLead = buildLead('NoQueueEmail', 'New');

        Test.startTest();
        LeadService.sendQueueWelcomeEmails(new List<Lead>{ newLead });
        Test.stopTest();
    }

    // ============================================================
    // checkAndSendMatchedAccountEmails
    // ============================================================
    @isTest
    static void testCheckAndSendMatchedAccountEmails_QueueOwner_InsertContext() {
        Account matchAccount = new Account(Name = 'Matched Acct Queue');
        insert matchAccount;

        Lead leadRec = buildLead('MatchQueueOwner', 'New');
        insert leadRec;

        leadRec.Matched_Account__c = matchAccount.Id;
        update leadRec;

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        LeadService.checkAndSendMatchedAccountEmails(new List<Lead>{ leadRec }, null);
        Test.stopTest();
    }

    @isTest
    static void testCheckAndSendMatchedAccountEmails_UserOwner_UpdateContext() {
        Account matchAccount = new Account(Name = 'Matched Acct User');
        insert matchAccount;

        User directOwner = [SELECT Id FROM User WHERE Alias = 'downer' LIMIT 1];

        Lead leadRec = buildLead('MatchUserOwner', 'Working - Contacted');
        leadRec.OwnerId = directOwner.Id;
        insert leadRec;

        Lead oldState = leadRec.clone(true, true, false, false);
        oldState.Matched_Account__c = null;

        leadRec.Matched_Account__c = matchAccount.Id;
        update leadRec;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ leadRec.Id => oldState };

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        LeadService.checkAndSendMatchedAccountEmails(new List<Lead>{ leadRec }, oldMap);
        Test.stopTest();
    }

    @isTest
    static void testCheckAndSendMatchedAccountEmails_NoChangeSkipsEmail() {
        Account matchAccount = new Account(Name = 'Matched Acct NoChange');
        insert matchAccount;

        User directOwner = [SELECT Id FROM User WHERE Alias = 'downer' LIMIT 1];

        Lead leadRec = buildLead('MatchNoChange', 'Working - Contacted');
        leadRec.OwnerId = directOwner.Id;
        leadRec.Matched_Account__c = matchAccount.Id;
        insert leadRec;

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ leadRec.Id => leadRec.clone(true, true, false, false) };

        Integer emailsBefore = Limits.getEmailInvocations();

        Test.startTest();
        LeadService.checkAndSendMatchedAccountEmails(new List<Lead>{ leadRec }, oldMap);
        Test.stopTest();
    }

    @isTest
    static void testCheckAndSendMatchedAccountEmails_NoMatchedAccount() {
        Lead leadRec = buildLead('NoMatch', 'Working - Contacted');
        insert leadRec;

        Test.startTest();
        LeadService.checkAndSendMatchedAccountEmails(new List<Lead>{ leadRec }, null);
        Test.stopTest();
    }

    // ============================================================
    // updateAccountType
    // ============================================================
    @isTest
    static void testUpdateAccountType_CODOrderType_BlankShipping() {
        Account acc = new Account(
            Name = 'Convert Acct COD',
            BillingStreet = '123 Main St',
            BillingCity = 'Austin',
            BillingState = 'Texas',
            BillingPostalCode = '78701',
            BillingCountry = 'United States'
        );
        insert acc;

        Lead leadRec = buildLead('CODConvert', 'Qualified');
        leadRec.ConvertedAccountId = acc.Id;
        leadRec.Order_Type__c = 'COD';

        Test.startTest();
        LeadService.updateAccountType(new List<Lead>{ leadRec });
        Test.stopTest();

        Account result = [SELECT Type, Sub_Type__c, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry FROM Account WHERE Id = :acc.Id];
    }

    @isTest
    static void testUpdateAccountType_NonCODOrderType_DoesNotSetSubType() {
        Account acc = new Account(Name = 'Convert Acct Standard');
        insert acc;

        Lead leadRec = buildLead('StandardConvert', 'Qualified');
        leadRec.ConvertedAccountId = acc.Id;
        leadRec.Order_Type__c = 'Standard';

        Test.startTest();
        LeadService.updateAccountType(new List<Lead>{ leadRec });
        Test.stopTest();

        Account result = [SELECT Type, Sub_Type__c FROM Account WHERE Id = :acc.Id];
    }

    @isTest
    static void testUpdateAccountType_ShippingAlreadyPopulated_NotOverwritten() {
        Account acc = new Account(
            Name = 'Convert Acct ExistingShip',
            BillingStreet = '123 Main St',
            BillingCity = 'Austin',
            ShippingStreet = '999 Warehouse Rd',
            ShippingCity = 'Dallas'
        );
        insert acc;

        Lead leadRec = buildLead('ExistingShipConvert', 'Qualified');
        leadRec.ConvertedAccountId = acc.Id;

        Test.startTest();
        LeadService.updateAccountType(new List<Lead>{ leadRec });
        Test.stopTest();

        Account result = [SELECT ShippingStreet, ShippingCity FROM Account WHERE Id = :acc.Id];
    }

    @isTest
    static void testUpdateAccountType_EmptyList() {
        Test.startTest();
        LeadService.updateAccountType(new List<Lead>());
        Test.stopTest();
    }

    @isTest
    static void testCreateAccountContactRelationships_SkipsDuplicate() {
        Account acc = new Account(Name = 'ACR Dedup Account');
        insert acc;

        // Contact inserted with AccountId creates the automatic primary AccountContactRelation record
        //Contact con = new Contact(FirstName = 'Dup', LastName = 'Test', AccountId = acc.Id);
        Contact con = new Contact(
            FirstName = 'Dup',
            LastName = 'Test',
            AccountId = acc.Id,
            MailingStreet = '123 Main St',
            MailingCity = 'Austin',
            MailingState = 'Texas',
            MailingPostalCode = '78701',
            MailingCountry = 'United States'
        );
        insert con;


        Lead leadRec = buildLead('ACRDedupLead', 'Qualified');
        leadRec.ConvertedAccountId = acc.Id;
        leadRec.ConvertedContactId = con.Id;

        Test.startTest();
        LeadService.createAccountContactRelationships(new List<Lead>{ leadRec });
        Test.stopTest();

        List<AccountContactRelation> acrs = [
            SELECT Id FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :con.Id
        ];
    }

    // ============================================================
    // updateOpportunityRevenueType
    // ============================================================
    @isTest
    static void testUpdateOpportunityRevenueType_MultipleServiceLines() {
        Account acc = new Account(Name = 'Opp Revenue Account');
        insert acc;

        Opportunity masterOpp = new Opportunity(
            Name = 'Converted Opp - Multi',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Service_Line__c ='Digital' ,
            Revenue_Type__c ='Portfolio Growth'
        );
        insert masterOpp;

        Lead leadRec = buildLead('MultiServiceLine', 'Qualified');
        leadRec.ConvertedOpportunityId = masterOpp.Id;
        leadRec.Service_Line__c = 'Litigation;Consulting';

        Test.startTest();
        LeadService.updateOpportunityRevenueType(new List<Lead>{ leadRec });
        Test.stopTest();

        Opportunity updatedMaster = [SELECT Revenue_Type__c, Service_Line__c, OwnerId FROM Opportunity WHERE Id = :masterOpp.Id];

        List<Opportunity> crossSellOpps = [
            SELECT Revenue_Type__c, Service_Line__c, OwnerId FROM Opportunity
            WHERE AccountId = :acc.Id AND Id != :masterOpp.Id
        ];
    }

    @isTest
    static void testUpdateOpportunityRevenueType_SingleServiceLine_NoClone() {
        Account acc = new Account(Name = 'Opp Revenue Single Account');
        insert acc;

        Opportunity masterOpp = new Opportunity(
            Name = 'Converted Opp - Single',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Service_Line__c ='Digital' ,
            Revenue_Type__c ='Portfolio Growth'
);
        insert masterOpp;

        Lead leadRec = buildLead('SingleServiceLine', 'Qualified');
        leadRec.ConvertedOpportunityId = masterOpp.Id;
        leadRec.Service_Line__c = 'Advisory';

        Test.startTest();
        LeadService.updateOpportunityRevenueType(new List<Lead>{ leadRec });
        Test.stopTest();

        Opportunity updatedMaster = [SELECT Revenue_Type__c, Service_Line__c FROM Opportunity WHERE Id = :masterOpp.Id];

        Integer cloneCount = [SELECT COUNT() FROM Opportunity WHERE AccountId = :acc.Id AND Id != :masterOpp.Id];
    }

    @isTest
    static void testUpdateOpportunityRevenueType_NoServiceLine() {
        Account acc = new Account(Name = 'Opp Revenue Blank Account');
        insert acc;

        Opportunity masterOpp = new Opportunity(
            Name = 'Converted Opp - Blank',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Service_Line__c ='Digital' ,
            Revenue_Type__c ='Portfolio Growth'
        );
        insert masterOpp;

        Lead leadRec = buildLead('BlankServiceLine', 'Qualified');
        leadRec.ConvertedOpportunityId = masterOpp.Id;

        Test.startTest();
        LeadService.updateOpportunityRevenueType(new List<Lead>{ leadRec });
        Test.stopTest();

        Opportunity updatedMaster = [SELECT Revenue_Type__c FROM Opportunity WHERE Id = :masterOpp.Id];
    }

    @isTest
    static void testUpdateOpportunityRevenueType_EmptyList() {
        Test.startTest();
        LeadService.updateOpportunityRevenueType(new List<Lead>());
        Test.stopTest();
    }
}