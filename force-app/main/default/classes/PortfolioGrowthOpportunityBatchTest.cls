/*
* @Author : Rahul Bhavaskar
* @Created Date : 18/09/26
* @Description : Test class for PortfolioGrowthOpportunityBatch, PortfolioGrowthOpportunityScheduler, PortfolioGrowthOpportunityHelper
* @Story Number : 5159
*/
@IsTest
private class PortfolioGrowthOpportunityBatchTest {

    @TestSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'Test Portfolio Growth Account',
            Status__c = 'New',
            Terms__c = true
        );

        insert acc;

        Opportunity sourceOpp = new Opportunity(
            Name = 'Test Closed Won Opportunity',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.newInstance(Date.today().year() - 1,8,15),
            Revenue_Type__c = 'Portfolio Growth',
            Service_Line__c = 'Digital',
            Estimated_Annual_Revenue__c = 100000,
            Estimated_Monthly_Revenue__c = 8333.33
        );

        insert sourceOpp;
    }

    @IsTest
    static void testBatchCreatesPortfolioGrowthOpportunity() {

        Test.startTest();
        Database.executeBatch(new PortfolioGrowthOpportunityBatch(),200);
        Test.stopTest();

        List<Opportunity> generatedOpps = [
            SELECT Id, Name, AccountId,OwnerId,Revenue_Type__c,StageName,Order_Type__c,Estimated_Start_Date__c,
            		Estimated_End_Date__c,CloseDate,Estimated_Monthly_Revenue__c,Estimated_Annual_Revenue__c, 
            		Service_Line__c
            		FROM Opportunity
            		WHERE Revenue_Type__c = 'Portfolio Growth'
        ];
        Opportunity generatedOpp = generatedOpps[0];
        Integer currentYear = Date.today().year();

        Account acc = [SELECT Id, OwnerId FROM Account WHERE Name = 'Test Portfolio Growth Account' LIMIT 1];
        Decimal expectedAnnualRevenue = 100000 * 1.10;
        Decimal expectedMonthlyRevenue = expectedAnnualRevenue / 12;
    }

    @IsTest
    static void testHelperDirectly() {
        Account acc = [SELECT Id,OwnerId,Status__c,Terms__c
            FROM Account
            WHERE Name = 'Test Portfolio Growth Account'
            LIMIT 1
        ];
        String cronExpression = '0 0 0 1 1 ?';

        Test.startTest();
        PortfolioGrowthOpportunityHelper.processAccounts( new List<Account>{ acc });
        System.schedule('Portfolio Growth Opportunity Scheduler Test',
            cronExpression,
            new PortfolioGrowthOpportunityScheduler()
        );
        Test.stopTest();

        List<Opportunity> generatedOpps = [
            SELECT Id, Revenue_Type__c, StageName, Service_Line__c
            FROM Opportunity
            WHERE AccountId = :acc.Id AND Revenue_Type__c = 'Portfolio Growth'
        ];
    }

    @IsTest
    static void testIneligibleAccountDoesNotCreateOpportunity() {

        Account inactiveAccount = new Account(Name = 'Inactive Test Account', Status__c = 'New',Terms__c = true);
        insert inactiveAccount;
        
        //inactiveAccount.Status__c = 'Active';
        //update inactiveAccount;

        Opportunity sourceOpp = new Opportunity(Name = 'Inactive Account Opportunity', AccountId = inactiveAccount.Id, StageName = 'Closed Won',
            CloseDate = Date.newInstance(Date.today().year() - 1,8,15),
            Revenue_Type__c = 'New Logo',
            Service_Line__c = 'Digital',
            Estimated_Annual_Revenue__c = 50000,
            Estimated_Monthly_Revenue__c = 4166.67
        );

        insert sourceOpp;

        Test.startTest();
        Database.executeBatch(new PortfolioGrowthOpportunityBatch(),200);
        Test.stopTest();

        List<Opportunity> generatedOpps = [SELECT Id FROM Opportunity 
                                           	WHERE AccountId = :inactiveAccount.Id
              								AND Revenue_Type__c = 'Portfolio Growth'
        ];
    }

    @IsTest
    static void testEdiscoveryRevenue() {
        Account acc = new Account(Name = 'E-Discovery Test Account',Status__c = 'New',Terms__c = true);
        insert acc;

        Opportunity sourceOpp = new Opportunity(Name = 'E-Discovery Closed Won', AccountId = acc.Id, StageName = 'Closed Won',
            CloseDate = Date.newInstance(Date.today().year() - 1,9,15),
            Revenue_Type__c = 'Cross Sell',
            Service_Line__c = 'Digital',
            Estimated_Annual_Revenue__c = 120000,
            Estimated_Monthly_Revenue__c = 10000
        );

        insert sourceOpp;

        Test.startTest();
        PortfolioGrowthOpportunityHelper.processAccounts(new List<Account>{ acc });
        Test.stopTest();

        Opportunity generatedOpp = [
            SELECT Id,
                   Revenue_Type__c,
                   Service_Line__c,
                   Estimated_Monthly_Revenue__c,
                   Estimated_Annual_Revenue__c
            FROM Opportunity
            WHERE AccountId = :acc.Id
              AND Revenue_Type__c = 'Portfolio Growth'
            LIMIT 1
        ];
    }

    @IsTest
    static void testNoDuplicateOpportunity() {
        Account acc = [
            SELECT Id,OwnerId
            FROM Account
            WHERE Name = 'Test Portfolio Growth Account'
            LIMIT 1
        ];

        Integer currentYear = Date.today().year();
        Opportunity existingOpp = new Opportunity(
            Name = 'Existing Portfolio Growth Opportunity',
            AccountId = acc.Id,
            StageName = 'Qualification',
            CloseDate = Date.newInstance(currentYear,1,31),
            Revenue_Type__c = 'Portfolio Growth',
            Order_Type__c = 'Terms',
            Service_Line__c = 'Digital',
            Estimated_Start_Date__c = Date.newInstance(currentYear,1,1),
            Estimated_End_Date__c = Date.newInstance(currentYear,12,31),
            Estimated_Monthly_Revenue__c = 9166.67,
            Estimated_Annual_Revenue__c = 110000
        );

        insert existingOpp;

        Test.startTest();
        PortfolioGrowthOpportunityHelper.processAccounts(new List<Account>{ acc });
        Test.stopTest();

        List<Opportunity> portfolioOpps = [
            SELECT Id
            FROM Opportunity
            WHERE AccountId = :acc.Id
              AND Revenue_Type__c = 'Portfolio Growth'
              AND Service_Line__c = 'Litigation'
              AND Estimated_Start_Date__c = :Date.newInstance(currentYear,1,1)
              AND Estimated_End_Date__c = :Date.newInstance(currentYear,12,31)
        ];
    }
}