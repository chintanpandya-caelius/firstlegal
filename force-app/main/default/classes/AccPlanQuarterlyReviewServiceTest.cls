@isTest
private class AccPlanQuarterlyReviewServiceTest {

    @testSetup
    static void setupTestData() {
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User salesOps = new User(
            LastName = 'Operations User',
            FirstName = 'Sales',
            Email = 'salesops@test-org-context.com',
            Username = 'salesops_' + DateTime.now().getTime() + '@testorg.com',
            Alias = 'slsops',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            IsActive = true
        );
        insert salesOps;

        User mgr = new User(
            LastName = 'Manager',
            FirstName = 'Test',
            Email = 'manager@test-org-context.com',
            Username = 'manager_' + DateTime.now().getTime() + '@testorg.com',
            Alias = 'mngrtst',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            IsActive = true
        );
        insert mgr;

        User planOwner = new User(
            LastName = 'Owner',
            FirstName = 'Account',
            Email = 'owner@test-org-context.com',
            Username = 'owner_' + DateTime.now().getTime() + '@testorg.com',
            Alias = 'ownrtst',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            ManagerId = mgr.Id,
            IsActive = true
        );
        insert planOwner;

        User orphanOwner = new User(
            LastName = 'OrphanOwner',
            FirstName = 'Account',
            Email = 'orphan@test-org-context.com',
            Username = 'orphan_' + DateTime.now().getTime() + '@testorg.com',
            Alias = 'orphown',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = stdProfile.Id,
            IsActive = true
        );
        insert orphanOwner;

        System.runAs(planOwner) {
            Account acc1 = new Account(Name = 'Enterprise Client Account');
            insert acc1;

            AccountPlan plan1 = new AccountPlan(
                Name = 'Enterprise Plan 2026',
                AccountId = acc1.Id,
                Status = 'Active'
            );
            insert plan1;
        }

        System.runAs(orphanOwner) {
            Account acc2 = new Account(Name = 'Orphan Client Account');
            insert acc2;

            AccountPlan plan2 = new AccountPlan(
                Name = 'Orphan Plan 2026',
                AccountId = acc2.Id,
                Status = 'Active'
            );
            insert plan2;

            AccountPlan plan3 = new AccountPlan(
                Name = 'Stale Plan',
                AccountId = acc2.Id,
                Status = 'Active'
            );
            insert plan3;
        }
    }

    @isTest
    static void testQuarterlyReviewTaskGeneration() {
        // Enclose within startTest/stopTest to refresh limits and mock asynchronous notification limits
        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        List<Task> createdTasks = [
            SELECT Id, OwnerId, WhatId, Subject, Status, Priority 
            FROM Task 
            WHERE Subject = 'Quarterly Account Plan Review'
        ];
        
        System.assert(createdTasks.size() >= 3, 'Should generate tasks for active plan accounts.');
        
        for (Task t : createdTasks) {
            System.assertEquals('Open', t.Status);
            System.assertEquals('Normal', t.Priority);
        }
    }

    @isTest
    static void testDuplicateCheckAndPrevention() {
        // Run first execution to generate initial tasks
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        
        List<Task> initialTasks = [SELECT Id FROM Task WHERE Subject = 'Quarterly Account Plan Review'];
        System.assertNotEquals(0, initialTasks.size(), 'Tasks must be generated during the first run.');

        Test.startTest();
        // Run second execution to assert deduplication
        AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        Test.stopTest();

        List<Task> postTasks = [SELECT Id FROM Task WHERE Subject = 'Quarterly Account Plan Review'];
        System.assertEquals(initialTasks.size(), postTasks.size(), 'Deduplication logic failed: duplicate tasks were generated.');
    }

    @isTest
    static void testInactivityMonitoringAndTransition() {
        // Fetch plans and update Created/LastModified dates in the past to simulate inactivity
        List<AccountPlan> plansToMakeStale = [SELECT Id FROM AccountPlan];
        for (AccountPlan plan : plansToMakeStale) {
            // Test.setCreatedDate is used to push dates back in test contexts
            Test.setCreatedDate(plan.Id, System.today().addMonths(-3));
        }

        Test.startTest();
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
        Test.stopTest();
        
        // Assert plans are transitioned to Inactive
        List<AccountPlan> currentPlans = [SELECT Id, Status FROM AccountPlan WHERE Status = 'Inactive'];
        System.assert(!currentPlans.isEmpty(), 'Stale plans should be transitioned to Inactive.');
    }

    @isTest
    static void testDailySchedulerTrigger() {
        Test.startTest();
        String cronTrigger = '0 0 2 * * ?';
        String jobId = System.schedule('Test Account Plan Scheduled Daily Job', cronTrigger, new AccountPlanQuarterlyReviewTaskScheduler());
        
        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(cronTrigger, ct.CronExpression);
        Test.stopTest();
    }
}