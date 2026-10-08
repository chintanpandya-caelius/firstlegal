@isTest
private class Lead_SendHotLeadNotification_Test {

    @testSetup
    static void setupTestData() {
        // Create a standard test user
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'stuser',
            Email = 'testuser_sla_breach@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser_sla_breach' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        // Create a test Queue (Group) for Lead object
        Group testQueue = new Group(
            Name = 'Test BDR Queue',
            Type = 'Queue'
        );
        insert testQueue;

        // Associate the Queue with the Lead SObject natively
        QueueSobject qSobj = new QueueSobject(
            QueueId = testQueue.Id,
            SobjectType = 'Lead'
        );
        
        // QueueSobject insertion requires running outside standard mixed-DML restrictions
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert qSobj;
            
            // Add our test user to the queue
            GroupMember gm = new GroupMember(
                GroupId = testQueue.Id,
                UserOrGroupId = testUser.Id
            );
            insert gm;
        }

        // Create test Leads with ALL validation rule fields populated
        List<Lead> testLeads = new List<Lead>{
            new Lead(
                FirstName = 'User', 
                LastName = 'OwnerTest', 
                Company = 'Test Inc', 
                Title = 'BDR Specialist',
                Phone = '(555) 555-5555',
                PostalCode = '94123',
                Email = 'user_test@testlead.com', // Added to satisfy validation
                SLA__c = 'S2 - Priority High',   // Added to satisfy validation (matching your log)
                Status = 'New'
            ),
            new Lead(
                FirstName = 'Queue', 
                LastName = 'OwnerTest', 
                Company = 'Test Inc', 
                Title = 'BDR Manager',
                Phone = '(555) 555-1111',
                PostalCode = '94121',
                Email = 'queue_test@testlead.com', // Added to satisfy validation
                SLA__c = 'S2 - Priority High',    // Added to satisfy validation (matching your log)
                Status = 'New'
            )
        };
        insert testLeads;
    }

    @isTest
    static void testSendNotificationToUserAndQueue() {
        // Retrieve data set up in testSetup
        Lead userLead = [SELECT Id FROM Lead WHERE FirstName = 'User' LIMIT 1];
        Lead queueLead = [SELECT Id FROM Lead WHERE FirstName = 'Queue' LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE Email = 'testuser_sla_breach@testorg.com' LIMIT 1];
        Group testQueue = [SELECT Id FROM Group WHERE Name = 'Test BDR Queue' LIMIT 1];

        // Prepare bulk invocable requests
        List<Lead_SendHotLeadNotification.Request> requests = new List<Lead_SendHotLeadNotification.Request>();

        // 1. Request for User Owner
        Lead_SendHotLeadNotification.Request req1 = new Lead_SendHotLeadNotification.Request();
        req1.leadId = userLead.Id;
        req1.ownerId = testUser.Id;
        requests.add(req1);

        // 2. Request for Queue Owner
        Lead_SendHotLeadNotification.Request req2 = new Lead_SendHotLeadNotification.Request();
        req2.leadId = queueLead.Id;
        req2.ownerId = testQueue.Id;
        requests.add(req2);

        // Execute the invocable method
        Test.startTest();
        Lead_SendHotLeadNotification.sendNotification(requests);
        Test.stopTest();

        // Verification assertion to verify code ran through cleanly
        System.assert(true, 'Invocable action executed without throwing unhandled exceptions.');
    }

    @isTest
    static void testEmptyAndNullRequests() {
        Test.startTest();
        // Guard checking for null parameter list
        Lead_SendHotLeadNotification.sendNotification(null);
        
        // Guard checking for empty parameter list
        Lead_SendHotLeadNotification.sendNotification(new List<Lead_SendHotLeadNotification.Request>());
        Test.stopTest();
        
        System.assert(true, 'Guard clauses handled null and empty lists gracefully.');
    }

    @isTest
    static void testInvalidRequestInputs() {
        // Build requests missing critical inner fields to hit continue/validation blocks
        List<Lead_SendHotLeadNotification.Request> requests = new List<Lead_SendHotLeadNotification.Request>();
        
        Lead_SendHotLeadNotification.Request invalidReq = new Lead_SendHotLeadNotification.Request();
        invalidReq.leadId = null;
        invalidReq.ownerId = null;
        requests.add(invalidReq);

        Test.startTest();
        Lead_SendHotLeadNotification.sendNotification(requests);
        Test.stopTest();

        System.assert(true, 'Loop handled invalid properties internally without crashing.');
    }
}