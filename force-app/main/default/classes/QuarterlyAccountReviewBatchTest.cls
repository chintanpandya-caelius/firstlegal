/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Test class for QuarterlyAccountReviewBatch
* @Story Number : 9751
*/

@IsTest
private class QuarterlyAccountReviewBatchTest {

    @TestSetup
    static void setupData() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                AnnualRevenue = 100000 + (i * 10000),
                Status__c = 'New'
            ));
        }
        insert accounts;
    }

    @IsTest
    static void testQuarterlyAccountReviewBatch() {

        Test.startTest();
        Database.executeBatch(new QuarterlyAccountReviewBatch(),200);
        Test.stopTest();

        // Verify that the Accounts exist and were processed.
        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE 'Test Account%'
        ];
        System.assertEquals(5,accounts.size(),'Expected 5 test Accounts to exist.');

        // Verify Tasks created by AccountReviewService.
        List<Task> tasks = [
            SELECT Id, WhatId, Subject, Status
            FROM Task
            WHERE WhatId IN :accounts
        ];
        System.assert(tasks.size() > 0,'Expected Quarterly Account Review Tasks to be created.');

        // Verify that at least one Task is associated with each Account.
        Set<Id> accountIdsWithTasks = new Set<Id>();

        for (Task task : tasks) {
            accountIdsWithTasks.add(task.WhatId);
        }
        System.assertEquals(accounts.size(),accountIdsWithTasks.size(),'Every Account should have a Quarterly Review Task.');
    }

    @IsTest
    static void testBatchWithNoAccounts() {
        Test.startTest();
        Database.executeBatch(new QuarterlyAccountReviewBatch(),200);
        Test.stopTest();
    }
    
    @IsTest
    static void testSchedulerWithBothAutomationsEnabled() {
        Test.startTest();
        String jobId = System.schedule('Account Automation Scheduler Test','0 0 12 * * ?',new AccountAutomationScheduler());
        Test.stopTest();
    }
}