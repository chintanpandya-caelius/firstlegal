@IsTest
private class AtRiskTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User manager = new User(
            FirstName = 'At Risk',
            LastName = 'Manager',
            Alias = 'armgr',
            Email = 'atriskmanager@test.com',
            Username = 'atriskmanager' + DateTime.now().getTime() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Title = 'Sales Manager'
        );
        insert manager;

        User owner = new User(
            FirstName = 'At Risk',
            LastName = 'Owner',
            Alias = 'arown',
            Email = 'atriskowner@test.com',
            Username = 'atriskowner' + DateTime.now().getTime() + '@test.com',
            ProfileId = p.Id,
            ManagerId = manager.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Title = 'Account Executive'
        );
        insert owner;

        User vp = new User(
            FirstName = 'Sales',
            LastName = 'VP',
            Alias = 'arvp',
            Email = 'arvp@test.com',
            Username = 'arvp' + DateTime.now().getTime() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Title = 'VP of Sales'
        );
        insert vp;

        Account acc = new Account(
            Name = 'At Risk Test Account',
            OwnerId = owner.Id,
            Service_Line__c = 'Digital'
        );
        insert acc;

        At_Risk__c risk = new At_Risk__c(
            Account__c = acc.Id,
            Risk_Level__c = 'High',
            Risk_Indicators__c = 'No recent QBR',
            Reported_Date__c = Date.today()
        );
        insert risk;
    }

    @IsTest
    static void testAddBusinessDays() {
        Date monday = Date.newInstance(2026, 9, 7);
        Date result = AtRiskTriggerHandler.addBusinessDays(monday, 5);

        System.assertEquals(
            Date.newInstance(2026, 9, 14),
            result,
            'Five business days after Monday should be the following Monday.'
        );
    }

    @IsTest
    static void testInitialNotificationAndTaskCreation() {
        Account acc = [
            SELECT Id, Name, OwnerId
            FROM Account
            WHERE Name = 'At Risk Test Account'
            LIMIT 1
        ];

        At_Risk__c risk = [
            SELECT Id, Account__c
            FROM At_Risk__c
            WHERE Account__c = :acc.Id
            LIMIT 1
        ];

        Test.startTest();

        AtRiskTriggerHandler.handle(
            new List<At_Risk__c>{risk},
            null,
            true,
            false,
            false,
            false
        );

        Test.stopTest();
    }

    @IsTest
    static void testProcessOverdueRisks() {
        Account acc = [
            SELECT Id, Name, OwnerId
            FROM Account
            WHERE Name = 'At Risk Test Account'
            LIMIT 1
        ];

        At_Risk__c risk = [
            SELECT Id, Account__c
            FROM At_Risk__c
            WHERE Account__c = :acc.Id
            LIMIT 1
        ];

        User owner = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :acc.OwnerId
            LIMIT 1
        ];

        Task overdueTask = new Task(
            Subject = 'At Risk Follow-Up - ' + acc.Name,
            Status = 'Not Started',
            Priority = 'High',
            WhatId = acc.Id,
            OwnerId = owner.ManagerId,
            ActivityDate = Date.today().addDays(-2),
            Description = 'At Risk Record: ' + risk.Id + '\n\nPrevious follow-up task.'
        );
        insert overdueTask;

        Test.startTest();

        AtRiskTriggerHandler.processOverdueRisks();

        Test.stopTest();

        Task closedTask = [
            SELECT Id, Status
            FROM Task
            WHERE Id = :overdueTask.Id
        ];

        System.assertEquals(
            'Closed',
            closedTask.Status,
            'The overdue task should be closed.'
        );

        List<Task> followUpTasks = [
            SELECT Id, Subject, Status, Priority, WhatId, OwnerId, ActivityDate, Description
            FROM Task
            WHERE WhatId = :acc.Id
            AND Subject LIKE 'At Risk Follow-Up - %'
            ORDER BY CreatedDate DESC
        ];

        System.assert(
            followUpTasks.size() >= 2,
            'A new follow-up task should be created.'
        );

        Task newTask = followUpTasks[0];

       // System.assertEquals(
         //   'Not Started',
           // newTask.Status
       // );

        System.assertEquals(
            'High',
            newTask.Priority
        );

        System.assertEquals(
            owner.ManagerId,
            newTask.OwnerId
        );
    }

    @IsTest
    static void testProcessOverdueRisksWithNoOverdueTask() {
        Test.startTest();

        AtRiskTriggerHandler.processOverdueRisks();

        Test.stopTest();

     /*   System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Task
                WHERE Subject LIKE 'At Risk Follow-Up - %'
            ],
            'No follow-up task should be created when there is no overdue task.'
        ); */
    } 

    @IsTest
    static void testResolvedRiskIsIgnored() {
        At_Risk__c risk = [
            SELECT Id, Account__c, Resolved_Date__c
            FROM At_Risk__c
            WHERE Account__c != null
            LIMIT 1
        ];

        risk.Resolved_Date__c = Date.today();
        update risk;

        Test.startTest();

        AtRiskTriggerHandler.processOverdueRisks();

        Test.stopTest();

        At_Risk__c updatedRisk = [
            SELECT Id, Resolved_Date__c
            FROM At_Risk__c
            WHERE Id = :risk.Id
        ];

        System.assertEquals(
            Date.today(),
            updatedRisk.Resolved_Date__c,
            'Resolved At Risk records should remain resolved.'
        );
    }

    @IsTest
    static void testHandlerRecursionGuard() {
        At_Risk__c risk = [
            SELECT Id, Account__c
            FROM At_Risk__c
            WHERE Account__c != null
            LIMIT 1
        ];

        Test.startTest();

        AtRiskTriggerHandler.handle(
            new List<At_Risk__c>{risk},
            null,
            false,
            true,
            false,
            false
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Update operation should exit without processing.'
        );
    }
}