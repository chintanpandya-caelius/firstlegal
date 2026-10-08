/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Test class for AccountInactivityService
* @Story Number : 5450
*/

@IsTest
private class AccountInactivityServiceTest {

    @IsTest
    static void testInactiveAccountWithNoActivity() {

        Account acc = new Account(Name = 'Test Inactive Account');
        insert acc;

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        Test.startTest();
        AccountInactivityService.processAccounts(new List<Account>{ acc },config);
        Test.stopTest();

        List<Task> tasks = [SELECT Id,OwnerId,WhatId,Subject,Priority,Status,
                            ActivityDate,Description
            				FROM Task
            				WHERE WhatId = :acc.Id
          				];
    }

    @IsTest
    static void testActiveAccountWithRecentTask() {

        Account acc = new Account(Name = 'Recently Active Account');
        insert acc;

        Task recentTask = new Task(
            Subject = 'Recent Activity',
            WhatId = acc.Id,
            Status = 'Completed',
            ActivityDate = Date.today()
        );
        insert recentTask;

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        Test.startTest();
        AccountInactivityService.processAccounts(new List<Account>{ acc },config);
        Test.stopTest();

        List<Task> inactivityTasks = [SELECT Id FROM Task WHERE WhatId = :acc.Id];

    }

    @IsTest
    static void testInactiveAccountWithOldTask() {

        Account acc = new Account(Name = 'Old Activity Account');
        insert acc;

        Task oldTask = new Task(
            Subject = 'Old Activity',
            WhatId = acc.Id,
            Status = 'Completed',
            ActivityDate = Date.today().addMonths(-3)
        );
        insert oldTask;

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        Test.startTest();
        AccountInactivityService.processAccounts(new List<Account>{ acc },config);
        Test.stopTest();

        List<Task> inactivityTasks = [SELECT Id FROM Task WHERE WhatId = :acc.Id];
       
    }

    @IsTest
    static void testActiveAccountWithRecentEvent() {

        Account acc = new Account(Name = 'Recent Event Account');
        insert acc;

        Event recentEvent = new Event(
            Subject = 'Recent Account Meeting',
            WhatId = acc.Id,
            StartDateTime = System.now(),
            EndDateTime = System.now().addHours(1)
        );
        insert recentEvent;

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        Test.startTest();
        AccountInactivityService.processAccounts(new List<Account>{ acc },config);
        Test.stopTest();

        List<Task> inactivityTasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :acc.Id
        ];
    }

    @IsTest
    static void testNullAndEmptyAccounts() {

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        Test.startTest();
        AccountInactivityService.processAccounts(null, config);
        AccountInactivityService.processAccounts(new List<Account>(),config);
        Test.stopTest();
    }

    @IsTest
    static void testAccountWithOpenTask() {

        Account acc = new Account(Name = 'Account With Open Task');
        insert acc;

        Task openTask = new Task(
            Subject = 'Open Task',
            WhatId = acc.Id,
            Status = 'Not Started',
            ActivityDate = Date.today()
        );
        insert openTask;

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        Test.startTest();
        AccountInactivityService.processAccounts(new List<Account>{ acc },config);
        Test.stopTest();

        List<Task> inactivityTasks = [
            SELECT Id
            FROM Task
            WHERE WhatId = :acc.Id           
        ];
    }
}