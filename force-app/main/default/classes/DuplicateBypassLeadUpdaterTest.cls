@IsTest
private class DuplicateBypassLeadUpdaterTest {

    @TestSetup
    static void setupData() {
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Coverage',
            Company = 'Test Company',
            Status = 'Open - Not Contacted',
            Email='testinguser123@gmail.com',
            Title='Testing Title',
            Phone='9876543210',
            PostalCode = '12345',
            SLA_Tier__c = 'S1'
        );
        insert testLead;
    }

    @IsTest
    static void testUpdateLeadsSuccess() {
        Lead existingLead = [SELECT Id, LastName FROM Lead LIMIT 1];
        existingLead.LastName = 'Updated Coverage';

        DuplicateBypassLeadUpdater.Request req = new DuplicateBypassLeadUpdater.Request();
        req.leadRecord = existingLead;

        List<DuplicateBypassLeadUpdater.Request> requests = new List<DuplicateBypassLeadUpdater.Request>{ req };

        Test.startTest();
        DuplicateBypassLeadUpdater.updateLeads(requests);
        Test.stopTest();

        Lead updatedLead = [SELECT LastName FROM Lead WHERE Id = :existingLead.Id];
        System.assertEquals('Updated Coverage', updatedLead.LastName, 'The lead should be successfully updated.');
    }

    @IsTest
    static void testUpdateLeadsEmptyList() {
        List<DuplicateBypassLeadUpdater.Request> emptyRequests = new List<DuplicateBypassLeadUpdater.Request>();

        Test.startTest();
        DuplicateBypassLeadUpdater.updateLeads(emptyRequests);
        Test.stopTest();

        System.assert(true, 'Method should exit gracefully when given an empty list.');
    }

    @IsTest
    static void testUpdateLeadsNullChecks() {
        DuplicateBypassLeadUpdater.Request emptyReq = new DuplicateBypassLeadUpdater.Request();
        
        List<DuplicateBypassLeadUpdater.Request> requests = new List<DuplicateBypassLeadUpdater.Request>{ null, emptyReq };

        Test.startTest();
        DuplicateBypassLeadUpdater.updateLeads(requests);
        Test.stopTest();

        System.assert(true, 'Method should bypass null requests and empty leadRecords safely.');
    }
}