@IsTest
private class NovaCreateAndRouteChatTicketActionTest {

    @TestSetup
    static void setupTestData() {
        // Create Queue records in System.runAs to prevent Mixed DML exceptions
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Group> queues = new List<Group>{
                new Group(Name = 'FCP General', DeveloperName = 'FCP_General', Type = 'Queue'),
                new Group(Name = 'FSP General', DeveloperName = 'FSP_General_POD', Type = 'Queue'),
                // Note: FSP_Digital_POD is intentionally omitted here to test Safety Fallback logic
                new Group(Name = 'FSP Depo', DeveloperName = 'FSP_Deposition_POD', Type = 'Queue'),
                new Group(Name = 'FSP Court', DeveloperName = 'FSP_Court_Process_POD', Type = 'Queue'),
                new Group(Name = 'FSP Investigate', DeveloperName = 'FSP_Investigations_POD', Type = 'Queue'),
                new Group(Name = 'FSP Records', DeveloperName = 'FSP_Records_POD', Type = 'Queue'),
                new Group(Name = 'FSP Tech', DeveloperName = 'FSP_Tech_POD', Type = 'Queue'),
                new Group(Name = 'FSP Billing', DeveloperName = 'FSP_Financial_Billing_POD', Type = 'Queue'),
                new Group(Name = 'FCP Custom Pod', DeveloperName = 'FCP_Custom_POD', Type = 'Queue')
            };
            insert queues;

            List<QueueSobject> qSobjs = new List<QueueSobject>();
            for (Group q : queues) {
                qSobjs.add(new QueueSobject(QueueId = q.Id, SObjectType = 'Case'));
            }
            insert qSobjs;
        }

        // Test Accounts
        Account fcpAcc = new Account(Name = 'FCP Corp', Is_FCP_Customer__c = true, Assigned_POD__c = 'FCP_Custom_POD');
        Account fspAcc = new Account(Name = 'FSP Corp', Is_FCP_Customer__c = false);
        Account fcpNoPodAcc = new Account(Name = 'FCP No Pod', Is_FCP_Customer__c = true, Assigned_POD__c = 'Invalid_POD_Name');
        insert new List<Account>{ fcpAcc, fspAcc, fcpNoPodAcc };

        // Test Contacts
        Contact c1 = new Contact(LastName = 'Smith', Email = 'smith@fcpcorp.com', AccountId = fcpAcc.Id);
        Contact c2 = new Contact(LastName = 'Jones', Email = 'jones@fspcorp.com', AccountId = fspAcc.Id);
        Contact c3 = new Contact(LastName = 'Dupe1', Email = 'dupe@test.com', AccountId = fspAcc.Id);
        Contact c4 = new Contact(LastName = 'Dupe2', Email = 'dupe@test.com', AccountId = fspAcc.Id);
        insert new List<Contact>{ c1, c2, c3, c4 };
    }

    @IsTest
    static void testNullAndEmptyRequests() {
        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> nullResults =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(null);
        List<NovaCreateAndRouteChatTicketAction.Result> emptyResults =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(new List<NovaCreateAndRouteChatTicketAction.Request>());
        Test.stopTest();

        System.assertEquals(0, nullResults.size(), 'Null input should return empty list');
        System.assertEquals(0, emptyResults.size(), 'Empty list input should return empty list');
    }

    @IsTest
    static void testFCPRouting_PodQueue() {
        NovaCreateAndRouteChatTicketAction.Request req = new NovaCreateAndRouteChatTicketAction.Request();
        req.subject = 'Deposition scheduling issue';
        req.description = 'Need to reschedule court reporter';
        req.contactEmail = 'smith@fcpcorp.com';
        req.priority = 'High';
        req.caseType = 'Problem';

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess, 'Should succeed');
        System.assertEquals('FCP', results[0].classification, 'Should be FCP');
        System.assertNotEquals(null, results[0].caseId, 'Case ID should be populated');
        System.assertNotEquals(null, results[0].caseNumber, 'Case Number should be populated');
        System.assertEquals('FCP_Custom_POD', results[0].assignedQueueName, 'Should route to assigned POD queue');
    }

    @IsTest
    static void testFCPRouting_MissingPodFallback() {
        Account fcpNoPod = [SELECT Id FROM Account WHERE Name = 'FCP No Pod' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE Email = 'smith@fcpcorp.com' LIMIT 1];

        NovaCreateAndRouteChatTicketAction.Request req = new NovaCreateAndRouteChatTicketAction.Request();
        req.subject = 'FCP No Pod Issue';
        req.contactId = c.Id;
        req.accountId = fcpNoPod.Id;

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals('FCP', results[0].classification);
        System.assertEquals('FCP_General', results[0].assignedQueueName, 'Should fallback to FCP_General');
        System.assert(results[0].routingLog.contains('EC1/EC6 Fallback'));
    }

    @IsTest
    static void testFSPRouting_Divisions() {
        // Test Depo Division
        NovaCreateAndRouteChatTicketAction.Request reqDepo = new NovaCreateAndRouteChatTicketAction.Request();
        reqDepo.subject = 'Court reporter scheduling';
        reqDepo.chatReason = 'deposition court reporter transcript videography';

        // Test Court Process Division
        NovaCreateAndRouteChatTicketAction.Request reqCourt = new NovaCreateAndRouteChatTicketAction.Request();
        reqCourt.subject = 'eFiling issue';
        reqCourt.chatReason = 'efiling process serving courier';

        // Test Investigations Division
        NovaCreateAndRouteChatTicketAction.Request reqInvest = new NovaCreateAndRouteChatTicketAction.Request();
        reqInvest.subject = 'Background check';
        reqInvest.chatReason = 'investigation surveillance skip trace';

        // Test Records Division
        NovaCreateAndRouteChatTicketAction.Request reqRec = new NovaCreateAndRouteChatTicketAction.Request();
        reqRec.subject = 'Medical records';
        reqRec.chatReason = 'records retrieval medical records';

        // Test EDiscovery Division
        NovaCreateAndRouteChatTicketAction.Request reqTech = new NovaCreateAndRouteChatTicketAction.Request();
        reqTech.subject = 'E-Discovery support';
        reqTech.chatReason = 'ediscovery document review data processing';

        // Test Finance Division
        NovaCreateAndRouteChatTicketAction.Request reqFin = new NovaCreateAndRouteChatTicketAction.Request();
        reqFin.subject = 'Invoicing query';
        reqFin.chatReason = 'invoicing billing account balance';

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ reqDepo, reqCourt, reqInvest, reqRec, reqTech, reqFin }
            );
        Test.stopTest();

        System.assertEquals('FSP_Deposition_POD', results[0].assignedQueueName);
        System.assertEquals('FSP_Court_Process_POD', results[1].assignedQueueName);
        System.assertEquals('FSP_Investigations_POD', results[2].assignedQueueName);
        System.assertEquals('FSP_Records_POD', results[3].assignedQueueName);
        System.assertEquals('FSP_Tech_POD', results[4].assignedQueueName);
        System.assertEquals('FSP_Financial_Billing_POD', results[5].assignedQueueName);
    }

    @IsTest
    static void testFSPRouting_SafetyFallback() {
        // Digital division queue (FSP_Digital_POD) was intentionally omitted from setup to trigger safety fallback
        NovaCreateAndRouteChatTicketAction.Request req = new NovaCreateAndRouteChatTicketAction.Request();
        req.subject = 'Trial binder printing request';
        req.contactEmail = 'jones@fspcorp.com';
        req.chatReason = 'Trial support and digital scan';
        req.chatTranscript = 'Need trial support binder and imaging services.';

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals('FSP', results[0].classification);
        System.assertEquals('FSP_General_POD', results[0].assignedQueueName);
        System.assert(results[0].routingLog.contains('Safety Fallback'));
    }

    @IsTest
    static void testFSPRouting_GeneralFallbackScenarios() {
        // 1. Empty/Blank chat inputs
        NovaCreateAndRouteChatTicketAction.Request req1 = new NovaCreateAndRouteChatTicketAction.Request();
        req1.subject = 'Blank chat input';
        req1.chatReason = '   ';
        req1.chatTranscript = null;

        // 2. Tied keyword scores (1 match for Depo, 1 match for Finance)
        NovaCreateAndRouteChatTicketAction.Request req2 = new NovaCreateAndRouteChatTicketAction.Request();
        req2.subject = 'Tied keywords';
        req2.chatReason = 'deposition invoicing';

        // 3. No keyword match
        NovaCreateAndRouteChatTicketAction.Request req3 = new NovaCreateAndRouteChatTicketAction.Request();
        req3.subject = 'Unmatched keywords';
        req3.chatReason = 'hello world help please';

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ req1, req2, req3 }
            );
        Test.stopTest();

        System.assertEquals('FSP_General_POD', results[0].assignedQueueName);
        System.assert(results[0].routingLog.contains('EC4 Triggered: No intent or transcript signals'));

        System.assertEquals('FSP_General_POD', results[1].assignedQueueName);
        System.assert(results[1].routingLog.contains('EC4 Triggered: Tied scores'));

        System.assertEquals('FSP_General_POD', results[2].assignedQueueName);
        System.assert(results[2].routingLog.contains('EC4 Triggered: No keyword match'));
    }

    @IsTest
    static void testContactAndAccountEdgeCases() {
        // 1. Contact email with no matches (EC2)
        NovaCreateAndRouteChatTicketAction.Request reqNoContact = new NovaCreateAndRouteChatTicketAction.Request();
        reqNoContact.subject = 'Unknown Email';
        reqNoContact.contactEmail = 'unknown@nobody.com';

        // 2. Contact email with multiple matches (EC2)
        NovaCreateAndRouteChatTicketAction.Request reqMultiContact = new NovaCreateAndRouteChatTicketAction.Request();
        reqMultiContact.subject = 'Duplicate Email';
        reqMultiContact.contactEmail = 'dupe@test.com';

        // 3. Ambiguous Account flag set directly (EC3)
        NovaCreateAndRouteChatTicketAction.Request reqAmbiguousAcc = new NovaCreateAndRouteChatTicketAction.Request();
        reqAmbiguousAcc.subject = 'Ambiguous Account Flag';
        reqAmbiguousAcc.isAmbiguousAccount = true;

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ reqNoContact, reqMultiContact, reqAmbiguousAcc }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assert(results[0].routingLog.contains('No Contact found'));

        System.assertEquals(true, results[1].isSuccess);
        System.assert(results[1].routingLog.contains('Multiple Contacts matched'));

        System.assertEquals(true, results[2].isSuccess);
        System.assert(results[2].routingLog.contains('EC3 Triggered'));
    }

    @IsTest
    static void testExceptionHandling() {
        // Passing an invalid Contact ID format triggers a DmlException in the try block
        NovaCreateAndRouteChatTicketAction.Request req = new NovaCreateAndRouteChatTicketAction.Request();
        req.subject = 'Exception Test';
        req.contactId = '003000000000000AAA';

        Test.startTest();
        List<NovaCreateAndRouteChatTicketAction.Result> results =
            NovaCreateAndRouteChatTicketAction.createAndRouteTickets(
                new List<NovaCreateAndRouteChatTicketAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess, 'Should fail and trigger catch block');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be logged');
        System.assert(results[0].routingLog.contains('ERROR:'), 'Routing log should contain error prefix');
    }
}