@isTest
private class OpportunityHandlerTest {

    @testSetup
    static void setupTestData() {
        Account testAcc = new Account(
            Name = 'Lewis Brisbois Bisgaard & Smith, LLP',
            ShippingStreet = '2112 Pennsylvania Ave NW Suite 500'
        );
        insert testAcc;

        Account testAccNoAddress = new Account(
            Name = 'Acme Legal Services',
            ShippingStreet = ''
        );
        insert testAccNoAddress;
    }

    @isTest
    static void testOpportunityNamingWithCaseNumber() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Lewis Brisbois Bisgaard & Smith, LLP' LIMIT 1];

        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            CloseDate = Date.newInstance(2026, 5, 15),
            StageName = 'Prospecting',
            Service_Line__c = 'Records',
            Matter_Case_Number__c = 'JCCP',
            Revenue_Type__c ='Class Action'
            
        );

        Test.startTest();
        insert opp;
        Test.stopTest();

        Opportunity insertedOpp = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
      
    }

    @isTest
    static void testOpportunityNamingWithoutCaseNumber() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Lewis Brisbois Bisgaard & Smith, LLP' LIMIT 1];

        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            CloseDate = Date.newInstance(2026, 5, 15),
            StageName = 'Prospecting',
            Service_Line__c = 'Records',
            Revenue_Type__c ='Class Action',
            Matter_Case_Number__c ='xyz'
        );

        Test.startTest();
        insert opp;
        Test.stopTest();

        Opportunity insertedOpp = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
       
    }

    @isTest
    static void testBlankAddressFallback() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme Legal Services' LIMIT 1];

        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            CloseDate = Date.newInstance(2026, 1, 10),
            StageName = 'Prospecting',
            Service_Line__c = 'Digital',
            Revenue_Type__c ='Class Action',
            Matter_Case_Number__c ='xyz'
        );

        Test.startTest();
        insert opp;
        Test.stopTest();

        Opportunity insertedOpp = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
     
    }

    @isTest
    static void testDuplicatePreventionSingleAndInFlight() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Lewis Brisbois Bisgaard & Smith, LLP' LIMIT 1];

        // 1. Insert original record
        Opportunity opp1 = new Opportunity(
            AccountId = acc.Id,
            CloseDate = Date.newInstance(2026, 5, 15),
            StageName = 'Prospecting',
            Service_Line__c = 'Investigations',
            Revenue_Type__c ='Class Action',
            Matter_Case_Number__c ='xyz'
        );
        insert opp1;

        // 2. Attempt duplicate creation
        Opportunity opp2 = new Opportunity(
            AccountId = acc.Id,
            CloseDate = Date.newInstance(2026, 5, 15),
            StageName = 'Prospecting',
            Service_Line__c = 'Investigations',
            Matter_Case_Number__c ='xyz'
        );

        Test.startTest();
        try {
            insert opp2;
            System.assert(false, 'Expected DMLException due to duplicate Opportunity name.');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('already exists for this Account'), 
                'Expected duplicate error message.'
            );
        }
        Test.stopTest();
    }

 /*   @isTest
    static void testUpdateExistingOpportunityWithoutDuplicateError() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Lewis Brisbois Bisgaard & Smith, LLP' LIMIT 1];

        Opportunity opp = new Opportunity(
            AccountId = acc.Id,
            CloseDate = Date.newInstance(2026, 5, 15),
            StageName = 'Prospecting',
            Service_Line__c = 'E-Discovery',
            Revenue_Type__c ='Class Action',
            Matter_Case_Number__c ='xyz'
            
        );
        insert opp;

        Test.startTest();
        opp.StageName = 'Qualification';
        update opp; // Should succeed without firing false duplicate error
        Test.stopTest();

        Opportunity updatedOpp = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
       
    } */
}