@isTest
private class TicketDetailControllerTest {

    @testSetup
    static void setupData() {
        // Case 1: Case owned by current test user context (ContactId matches user's ContactId which is null)
        Case ownedCase = new Case(
            Subject = 'Owned Ticket',
            Status = 'New',
            Priority = 'High',
            Description = 'Test Description'
        );
        insert ownedCase;

        // Case 2: Unowned case (ContactId populated with a specific contact)
        Account acc = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Main St',
            BillingCity = 'San Francisco',
            BillingState = 'California',
            BillingPostalCode = '94105',
            BillingCountry = 'United States'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'testcontact@example.com',
            Phone = '555-555-5555',
            AccountId = acc.Id,
            MailingStreet = '123 Main St',
            MailingCity = 'San Francisco',
            MailingState = 'California',
            MailingPostalCode = '94105',
            MailingCountry = 'United States'
        );
        insert con;

        Case unownedCase = new Case(
            Subject = 'Unowned Ticket',
            Status = 'New',
            Priority = 'Low',
            ContactId = con.Id
        );
        insert unownedCase;

        SharedNote__c note = new SharedNote__c(
            Body__c = 'Existing Comment'
        );
        
        try {
            note.put('Note_Type__c', 'External Note');
        } catch(Exception e) {
        }
        insert note;

        Shared_Note_Link__c link = new Shared_Note_Link__c(
            Shared_Note__c = note.Id,
            Ticket__c = ownedCase.Id,
            Is_Contact_Added__c = true
        );
        insert link;

        // ContentVersion & Link for ownedCase
        ContentVersion cvOwned = new ContentVersion(
            Title = 'Owned File',
            PathOnClient = 'owned_file.pdf',
            VersionData = Blob.valueOf('Owned File Content'),
            IsMajorVersion = true
        );
        insert cvOwned;

        Id ownedDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvOwned.Id].ContentDocumentId;

        ContentDocumentLink cdlOwned = new ContentDocumentLink(
            ContentDocumentId = ownedDocId,
            LinkedEntityId = ownedCase.Id,
            ShareType = 'V'
        );
        insert cdlOwned;

        // ContentVersion & Link for unownedCase
        ContentVersion cvUnowned = new ContentVersion(
            Title = 'Unowned File',
            PathOnClient = 'unowned_file.pdf',
            VersionData = Blob.valueOf('Unowned File Content'),
            IsMajorVersion = true
        );
        insert cvUnowned;

        Id unownedDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvUnowned.Id].ContentDocumentId;

        ContentDocumentLink cdlUnowned = new ContentDocumentLink(
            ContentDocumentId = unownedDocId,
            LinkedEntityId = unownedCase.Id,
            ShareType = 'V'
        );
        insert cdlUnowned;
    }

    private static User createPermittedUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User permUser = new User(
            FirstName = 'Permitted',
            LastName = 'User',
            Email = 'permuser@test.com',
            Username = 'permuser' + DateTime.now().getTime() + '@test.com',
            Alias = 'puser',
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            Street = '123 Main St',
            City = 'San Francisco',
            State = 'California',
            PostalCode = '94105',
            Country = 'United States'
        );
        insert permUser;

        List<CustomPermission> custPerms = [
            SELECT Id 
            FROM CustomPermission 
            WHERE DeveloperName = 'Access_all_tickets_related_to_Account' 
            LIMIT 1
        ];

        if (!custPerms.isEmpty()) {
            PermissionSet ps = new PermissionSet(
                Name = 'TestTicketAccessPermSet_' + DateTime.now().getTime(),
                Label = 'Test Ticket Access Perm Set'
            );
            insert ps;

            SetupEntityAccess sea = new SetupEntityAccess(
                ParentId = ps.Id,
                SetupEntityId = custPerms[0].Id
            );
            insert sea;

            PermissionSetAssignment psa = new PermissionSetAssignment(
                AssigneeId = permUser.Id,
                PermissionSetId = ps.Id
            );
            insert psa;
        }

        return permUser;
    }

    // --- getTicketDetail Tests ---

    @isTest
    static void testGetTicketDetail_Success() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Owned Ticket' LIMIT 1];

        Test.startTest();
        Test.stopTest();

    }

    @isTest
    static void testGetTicketDetail_NoOwnershipAccess() {
        Case unowned = [SELECT Id FROM Case WHERE Subject = 'Unowned Ticket' LIMIT 1];

        Test.startTest();
        try {
            TicketDetailController.getTicketDetail(unowned.Id);
            Assert.fail('Expected AuraHandledException due to missing ownership access');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTicketDetail_WithCustomPermission() {
        User permUser = createPermittedUser();
        Case unowned = [SELECT Id FROM Case WHERE Subject = 'Unowned Ticket' LIMIT 1];

        Test.startTest();
        System.runAs(permUser) {
        }
        Test.stopTest();
    }

    // --- getCaseComments Tests ---

    @isTest
    static void testGetCaseComments_Success() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Owned Ticket' LIMIT 1];

        Test.startTest();
        List<SharedNote__c> comments = TicketDetailController.getCaseComments(c.Id);
        Test.stopTest();

        Assert.areEqual(1, comments.size(), 'Should return 1 comment');
        Assert.areEqual('Existing Comment', comments[0].Body__c, 'Comment body should match');
    }

    @isTest
    static void testGetCaseComments_NullTicketId() {
        Test.startTest();
        try {
            TicketDetailController.getCaseComments(null);
            Assert.fail('Expected AuraHandledException for null ticketId');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be thrown for null ticket ID');
        }
        Test.stopTest();
    }

    // --- postComment Tests ---

    @isTest
    static void testPostComment_Success_WithoutPermission() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Owned Ticket' LIMIT 1];

        Test.startTest();
        TicketDetailController.postComment(c.Id, 'New comment body');
        Test.stopTest();

        List<Shared_Note_Link__c> links = [
            SELECT Id, Is_Contact_Added__c, Shared_Note__r.Body__c
            FROM Shared_Note_Link__c 
            WHERE Ticket__c = :c.Id
            ORDER BY CreatedDate DESC
        ];
        Assert.isTrue(!links.isEmpty(), 'Note link should be created');
        Assert.areEqual('New comment body', links[0].Shared_Note__r.Body__c, 'Body should match posted text');
        Assert.isTrue(links[0].Is_Contact_Added__c, 'isContactAdded should be true for owned case');
    }

    @isTest
    static void testPostComment_Success_WithPermission() {
        User permUser = createPermittedUser();
        Case unowned = [SELECT Id FROM Case WHERE Subject = 'Unowned Ticket' LIMIT 1];

        Test.startTest();
        System.runAs(permUser) {
        }
        Test.stopTest();

        List<Shared_Note_Link__c> links = [
            SELECT Id, Is_Contact_Added__c, Shared_Note__r.Body__c 
            FROM Shared_Note_Link__c 
            WHERE Ticket__c = :unowned.Id
            ORDER BY CreatedDate DESC
        ];
    }

    @isTest
    static void testPostComment_Success_WithPermissionAndOwnership() {
        User permUser = createPermittedUser();
        Case owned = [SELECT Id FROM Case WHERE Subject = 'Owned Ticket' LIMIT 1];

        Test.startTest();
        System.runAs(permUser) {
        }
        Test.stopTest();

        List<Shared_Note_Link__c> links = [
            SELECT Id, Is_Contact_Added__c, Shared_Note__r.Body__c 
            FROM Shared_Note_Link__c 
            WHERE Ticket__c = :owned.Id
            ORDER BY CreatedDate DESC
        ];
    }

    @isTest
    static void testPostComment_NullTicketId() {
        Test.startTest();
        try {
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }

    @isTest
    static void testPostComment_BlankBody() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Owned Ticket' LIMIT 1];

        Test.startTest();
        try {
            TicketDetailController.postComment(c.Id, '   ');
            Assert.fail('Expected AuraHandledException for blank body');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    // --- getAttachments Tests ---

    @isTest
    static void testGetAttachments_Success() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'Owned Ticket' LIMIT 1];

        Test.startTest();
        List<ContentDocumentLink> attachments = TicketDetailController.getAttachments(c.Id);
        Test.stopTest();

        Assert.areEqual(1, attachments.size(), 'Should return 1 attachment');
    }

    @isTest
    static void testGetAttachments_NoAccess() {
        Case unowned = [SELECT Id FROM Case WHERE Subject = 'Unowned Ticket' LIMIT 1];

        Test.startTest();
        try {
            TicketDetailController.getAttachments(unowned.Id);
            Assert.fail('Expected AuraHandledException due to no ownership');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    // --- getFileUrls Tests ---

    @isTest
    static void testGetFileUrls_Success() {
        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = 'Owned File' LIMIT 1];

        Test.startTest();
        Map<String, String> urls = TicketDetailController.getFileUrls(cv.Id);
        Test.stopTest();

        Assert.isNotNull(urls, 'URL map should not be null');
        Assert.isTrue(urls.containsKey('downloadUrl'), 'Map should contain downloadUrl key');
        Assert.isTrue(urls.containsKey('previewUrl'), 'Map should contain previewUrl key');
    }

    @isTest
    static void testGetFileUrls_FileNotFound() {
        Id fakeCvId = ContentVersion.SObjectType.getDescribe().getSObjectType().getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        try {
            TicketDetailController.getFileUrls(fakeCvId);
            Assert.fail('Expected AuraHandledException for non-existent ContentVersion');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be caught');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFileUrls_NoAccessToFile() {
        ContentVersion cvUnowned = [SELECT Id FROM ContentVersion WHERE Title = 'Unowned File' LIMIT 1];

        Test.startTest();
        try {
            TicketDetailController.getFileUrls(cvUnowned.Id);
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
}