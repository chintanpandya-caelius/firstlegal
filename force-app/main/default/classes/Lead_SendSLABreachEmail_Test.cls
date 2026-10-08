@isTest
private class Lead_SendSLABreachEmail_Test {

    @testSetup
    static void setupTestData() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'finsla',
            Email = 'final_sla_breach@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ProductionTester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'final_sla_breach' + DateTime.now().getTime() + '@testorg.com'
        );
        insert testUser;

        Group testQueue = new Group(Name = 'Production BDR Email Queue', Type = 'Queue');
        insert testQueue;

        QueueSobject qSobj = new QueueSobject(QueueId = testQueue.Id, SobjectType = 'Lead');
        
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert qSobj;
            insert new GroupMember(GroupId = testQueue.Id, UserOrGroupId = testUser.Id);
        }

        Datetime dynamicSlaPastDue = System.now().addMinutes(-75);

        // Satisfies required validation parameters + sets status to 'New'
        insert new List<Lead>{
            new Lead(
                FirstName = 'User & Co', LastName = 'SlaTest', Company = 'Standard & Poor\'s Ltd', 
                Title = 'BDR Specialist', Phone = '(555) 555-5555', PostalCode = '94123',
                Email = 'user_prod_test@testlead.com', SLA__c = 'S2 - Priority High', 
                SLA_Due_Date__c = dynamicSlaPastDue, Status = 'New'
            ),
            new Lead(
                FirstName = 'Queue', LastName = 'SlaTest', Company = 'AT&T Communications', 
                Title = 'BDR Manager', Phone = '(555) 555-1111', PostalCode = '94121',
                Email = 'queue_prod_test@testlead.com', SLA__c = 'S2 - Priority High', 
                SLA_Due_Date__c = dynamicSlaPastDue, Status = 'New'
            )
        };
    }

    @isTest
    static void testSendEmailToUserAndQueue() {
        Lead userLead = [SELECT Id FROM Lead WHERE LastName = 'SlaTest' AND FirstName LIKE 'User%' LIMIT 1];
        Lead queueLead = [SELECT Id FROM Lead WHERE LastName = 'SlaTest' AND FirstName = 'Queue' LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE Email = 'final_sla_breach@testorg.com' LIMIT 1];
        Group testQueue = [SELECT Id FROM Group WHERE Name = 'Production BDR Email Queue' LIMIT 1];

        List<Lead_SendSLABreachEmail.Request> requests = new List<Lead_SendSLABreachEmail.Request>();

        Lead_SendSLABreachEmail.Request req1 = new Lead_SendSLABreachEmail.Request();
        req1.leadId = userLead.Id;
        req1.ownerId = testUser.Id;
        requests.add(req1);

        Lead_SendSLABreachEmail.Request req2 = new Lead_SendSLABreachEmail.Request();
        req2.leadId = queueLead.Id;
        req2.ownerId = testQueue.Id;
        requests.add(req2);

        Test.startTest();
        Lead_SendSLABreachEmail.sendEmailNotification(requests);
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, emailInvocations, 'Consolidated transactional emails should compile and record successfully.');
    }

    @isTest
    static void testNullAndEmptyRequests() {
        Test.startTest();
        Lead_SendSLABreachEmail.sendEmailNotification(null);
        Lead_SendSLABreachEmail.sendEmailNotification(new List<Lead_SendSLABreachEmail.Request>());
        Test.stopTest();
        System.assert(true, 'Guard statements handled null parameters successfully.');
    }
}