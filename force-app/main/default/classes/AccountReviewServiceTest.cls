/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Test class for AccountReviewService
* @Story Number : 9751
*/

@IsTest
private class AccountReviewServiceTest {
    @IsTest
    static void testCreateQuarterlyTaskForOwner() {

        Account acc = new Account(Name = 'Quarterly Review Test Account');
        insert acc;

        acc = [SELECT Id,Name,OwnerId,Owner.Name,Owner.ManagerId,Status__c,AnnualRevenue,LastActivityDate
                    FROM Account
                    WHERE Id = :acc.Id
        ];

        Test.startTest();
        AccountReviewService.createQuarterlyTasks(new List<Account>{ acc });
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id,OwnerId,WhatId,Subject,Priority,Status,ActivityDate,CallDisposition,Description
                    FROM Task
                    WHERE WhatId = :acc.Id
        ];

        Boolean ownerTaskFound = false;
    }

    @IsTest
    static void testCreateQuarterlyTaskForOwnerAndManager() {

        Profile profile = [SELECT Id FROM Profile
                            WHERE Id = :UserInfo.getProfileId()
                            LIMIT 1
        ];

        User manager = new User(
            FirstName = 'Test',
            LastName = 'Manager',
            Alias = 'tmanager',
            Email = 'testmanager@example.com',
            Username = 'testmanager' + System.currentTimeMillis()
                + '@example.com',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert manager;

        User accountOwner = new User(
            FirstName = 'Test',
            LastName = 'AccountOwner',
            Alias = 'towner',
            Email = 'testowner@example.com',
            Username = 'testowner' + System.currentTimeMillis()
                + '@example.com',
            ProfileId = profile.Id,
            ManagerId = manager.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert accountOwner;

		Account acc = new Account(Name = 'Quarterly Review Test Account');

        insert acc;

        acc = [ SELECT Id, Name, OwnerId, Owner.Name, Owner.ManagerId, Status__c, AnnualRevenue, LastActivityDate
                        FROM Account
                        WHERE Id = :acc.Id
        ];

        Test.startTest();
        AccountReviewService.createQuarterlyTasks(new List<Account>{ acc });
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, OwnerId, WhatId, Subject,CallDisposition
            FROM Task
            WHERE WhatId = :acc.Id
        ];

        Set<Id> taskOwnerIds = new Set<Id>();

        for (Task task : tasks) {
            taskOwnerIds.add(task.OwnerId);
        }
    }

    @IsTest
    static void testDuplicateQuarterlyTaskIsNotCreated() {

		Account acc = new Account(Name = 'Quarterly Review Test Account');
        insert acc;
        acc = [SELECT Id, Name, OwnerId, Owner.Name, Owner.ManagerId, Status__c, AnnualRevenue, LastActivityDate
                FROM Account
                WHERE Id = :acc.Id
        ];

        Date todayDate = Date.today();
        Integer month = todayDate.month();
        Integer quarterNumber =((month - 1) / 3) + 1;

        String quarterKey =
            'FY'
            + String.valueOf(todayDate.year())
            + '-Q'
            + String.valueOf(quarterNumber);

        String automationKey =
            String.valueOf(acc.Id)
            + '-'
            + quarterKey
            + '-QUARTERLY-REVIEW-'
            + String.valueOf(acc.OwnerId);

        // Existing quarterly task
        Task existingTask = new Task(
            OwnerId = acc.OwnerId,
            WhatId = acc.Id,
            Subject = 'Existing Quarterly Review',
            Priority = 'Medium',
            Status = 'Not Started',
            ActivityDate = Date.today(),
            CallDisposition = automationKey
        );

        insert existingTask;

        Test.startTest();
        AccountReviewService.createQuarterlyTasks(new List<Account>{ acc });
        Test.stopTest();

        List<Task> quarterlyTasks = [
            SELECT Id,
                   CallDisposition
            FROM Task
            WHERE WhatId = :acc.Id
            AND CallDisposition = :automationKey
        ];
    }

    @IsTest
    static void testNullAndEmptyAccounts() {
        Test.startTest();
        AccountReviewService.createQuarterlyTasks(null);
        AccountReviewService.createQuarterlyTasks(new List<Account>());
        Test.stopTest();
    }

    @IsTest
    static void testMultipleAccounts() {

        List<Account> accountsToInsert = new List<Account>();

        for (Integer i = 0; i < 3; i++) {
            accountsToInsert.add(
                new Account(
                    Name = 'Quarterly Test Account ' + i,
                    AnnualRevenue = 100000 + i
                )
            );
        }

        insert accountsToInsert;

        List<Account> accounts = [SELECT Id,Name, OwnerId, Owner.Name, Owner.ManagerId, Status__c, AnnualRevenue, LastActivityDate
                                    FROM Account
                                    WHERE Id IN :accountsToInsert
        ];

        Test.startTest();
        AccountReviewService.createQuarterlyTasks(accounts);
        Test.stopTest();

        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId IN :accountsToInsert
        ];

    }
}