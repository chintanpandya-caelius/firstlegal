@isTest
private class KPIGoalTriggerHandlerTest {

    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName = 'Test',
            LastName = 'KPIUser',
            Email = 'kpiuser@testorg.com',
            Username = 'kpiuser' + System.currentTimeMillis() + '@testorg.com',
            Alias = 'kpiu',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = p.Id,
            LanguageLocaleKey = 'en_US'
        );
        insert u;
    }

    @isTest
    static void testBeforeInsertSuccess() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'KPIUser' LIMIT 1];

        KPI_Goal__c goal = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Effective_From__c = Date.today(),
            Effective_To__c = Date.today().addDays(30)
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(goal, false);
        Test.stopTest();

        System.assert(result.isSuccess(), 'Valid KPI Goal should be inserted without errors.');
    }

    @isTest
    static void testBeforeInsertOverlapError() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'KPIUser' LIMIT 1];

        // Insert primary active goal
        KPI_Goal__c primaryGoal = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Effective_From__c = Date.today(),
            Effective_To__c = Date.today().addDays(30)
        );
        insert primaryGoal;

        // Create conflicting overlapping goal
        KPI_Goal__c conflictingGoal = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Effective_From__c = Date.today().addDays(10),
            Effective_To__c = Date.today().addDays(40)
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(conflictingGoal, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Conflicting active goal should trigger validation error.');
        System.assertEquals(
            'An active KPI Goal already exists for this User, Reporting Period, and date range. Please deactivate or adjust the date range of the conflicting goal.',
            result.getErrors()[0].getMessage()
        );
    }

    @isTest
    static void testBeforeUpdateOverlapError() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'KPIUser' LIMIT 1];

        // Insert two distinct, non-overlapping goals
        KPI_Goal__c goal1 = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Effective_From__c = Date.today(),
            Effective_To__c = Date.today().addDays(10)
        );

        KPI_Goal__c goal2 = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Effective_From__c = Date.today().addDays(20),
            Effective_To__c = Date.today().addDays(30)
        );
        insert new List<KPI_Goal__c>{ goal1, goal2 };

        // Update goal2 range to overlap with goal1
        goal2.Effective_From__c = Date.today().addDays(5);

        Test.startTest();
        Database.SaveResult result = Database.update(goal2, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Updating date range to create an overlap should fail validation.');
    }

    @isTest
    static void testBypassForInactiveAndGlobalGoals() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'KPIUser' LIMIT 1];

        // Inactive goal
        KPI_Goal__c inactiveGoal = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Monthly',
            Active__c = false,
            Effective_From__c = Date.today(),
            Effective_To__c = Date.today().addDays(30)
        );

        // Global goal without user assignment
        KPI_Goal__c globalGoal = new KPI_Goal__c(
            User__c = null,
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Effective_From__c = Date.today(),
            Effective_To__c = Date.today().addDays(30)
        );

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(new List<KPI_Goal__c>{ inactiveGoal, globalGoal }, false);
        Test.stopTest();

        for (Database.SaveResult res : results) {
            System.assert(res.isSuccess(), 'Inactive goals or goals with no User should bypass validation.');
        }
    }

    @isTest
    static void testNullDateRangeOverlap() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'KPIUser' LIMIT 1];

        // Open-ended goal (null dates default to 1900–4000)
        KPI_Goal__c openEndedGoal = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Weekly',
            Active__c = true,
            Effective_From__c = null,
            Effective_To__c = null
        );
        insert openEndedGoal;

        // Specific date goal that clashes with open-ended goal
        KPI_Goal__c specificGoal = new KPI_Goal__c(
            User__c = testUser.Id,
            Reporting_Period__c = 'Weekly',
            Active__c = true,
            Effective_From__c = Date.today(),
            Effective_To__c = Date.today().addDays(7)
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(specificGoal, false);
        Test.stopTest();

        System.assert(!result.isSuccess(), 'Goal should clash with an existing open-ended range goal.');
    }
}