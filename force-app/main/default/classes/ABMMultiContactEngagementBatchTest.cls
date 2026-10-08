@IsTest
private class ABMMultiContactEngagementBatchTest {

    @TestSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'ABM Test Account'
        );
        insert acc;


        List<Contact> contacts = new List<Contact>();

        for (Integer i = 0; i < 3; i++) {

            contacts.add(
                new Contact(
                    FirstName = 'Test',
                    LastName = 'Contact ' + i,
                    AccountId = acc.Id
                )
            );
        }

        insert contacts;


        List<Task> qualifyingTasks = new List<Task>();

        for (Integer i = 0; i < 3; i++) {

            qualifyingTasks.add(
                new Task(
                    Subject = '[ABM Signal] - Test Engagement ' + i,
                    WhoId = contacts[i].Id,
                    Status = 'Completed'
                )
            );
        }

        insert qualifyingTasks;


        Datetime recentDate = System.now().addDays(-2);

        for (Task taskRecord : qualifyingTasks) {
            Test.setCreatedDate(
                taskRecord.Id,
                recentDate
            );
        }
    }


    @IsTest
    static void testMCLECreation() {

        Test.startTest();

        Database.executeBatch(
            new ABMMultiContactEngagementBatch(),
            200
        );

        Test.stopTest();


        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'ABM Test Account'
            LIMIT 1
        ];


        List<Task> mcleTasks = [
            SELECT Id,
                   Subject,
                   WhatId,
                   Status,
                   Signal_Type__c,
                   Engagement_Channel__c,
                   ABM_Behavioral_Signal__c
            FROM Task
            WHERE WhatId = :acc.Id
            AND Subject LIKE
                '[ABM Signal] - Multi-Contact Account Engagement%'
        ];


        System.assertEquals(
            1,
            mcleTasks.size(),
            'One MCLE Task should be created'
        );


        Task mcleTask = mcleTasks[0];

        System.assertEquals(
            'Completed',
            mcleTask.Status
        );

        System.assertEquals(
            'Multi-Contact Account Engagement',
            mcleTask.Signal_Type__c
        );

        System.assertEquals(
            'Account Rollup',
            mcleTask.Engagement_Channel__c
        );

        System.assertEquals(
            true,
            mcleTask.ABM_Behavioral_Signal__c
        );
    }


    @IsTest
    static void testNoDuplicateMCLEWithoutNewTask() {

        Test.startTest();

        Database.executeBatch(
            new ABMMultiContactEngagementBatch(),
            200
        );

        Test.stopTest();


        Test.startTest();

        Database.executeBatch(
            new ABMMultiContactEngagementBatch(),
            200
        );

        Test.stopTest();


        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'ABM Test Account'
            LIMIT 1
        ];


        Integer mcleCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :acc.Id
            AND Subject LIKE
                '[ABM Signal] - Multi-Contact Account Engagement%'
        ];


        System.assertEquals(
            1,
            mcleCount,
            'Duplicate MCLE Task should not be created'
        );
    }


    @IsTest
    static void testHighFrequencyCreation() {

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'ABM Test Account'
            LIMIT 1
        ];


        /*
         * Create 3 MCLE Tasks directly on Account.
         */
        List<Task> mcleTasks = new List<Task>();

        for (Integer i = 0; i < 3; i++) {

            mcleTasks.add(
                new Task(
                    Subject =
                        '[ABM Signal] - Multi-Contact Account Engagement - Test ' +
                        i,
                    WhatId = acc.Id,
                    Status = 'Completed',
                    ABM_Behavioral_Signal__c = true,
                    Signal_Type__c =
                        'Multi-Contact Account Engagement',
                    Engagement_Channel__c =
                        'Account Rollup'
                )
            );
        }

        insert mcleTasks;


        Datetime recentDate = System.now().addDays(-5);

        for (Task taskRecord : mcleTasks) {
            Test.setCreatedDate(
                taskRecord.Id,
                recentDate
            );
        }


        Test.startTest();

        Database.executeBatch(
            new ABMMultiContactEngagementBatch(),
            200
        );

        Test.stopTest();


        List<Task> frequencyTasks = [
            SELECT Id,
                   Subject,
                   Status,
                   Signal_Frequency_Event__c
            FROM Task
            WHERE WhatId = :acc.Id
            AND Subject LIKE
                '[ABM Signal] - High Frequency Signal Activity%'
        ];


        System.assertEquals(
            1,
            frequencyTasks.size(),
            'High Frequency Activity Task should be created'
        );

        System.assertEquals(
            'Completed',
            frequencyTasks[0].Status
        );

        System.assertEquals(
            true,
            frequencyTasks[0].Signal_Frequency_Event__c
        );


        List<Task> reviewTasks = [
            SELECT Id,
                   Subject,
                   Priority,
                   Type,
                   Signal_Review_Required__c
            FROM Task
            WHERE WhatId = :acc.Id
            AND Subject LIKE
                'Review Elevated ABM Behavioral Signal Activity%'
        ];


        System.assertEquals(
            1,
            reviewTasks.size(),
            'One High Frequency Review Task should be created'
        );

        System.assertEquals(
            'High',
            reviewTasks[0].Priority
        );

        System.assertEquals(
            'ABM Signal Review',
            reviewTasks[0].Type
        );

        System.assertEquals(
            true,
            reviewTasks[0].Signal_Review_Required__c
        );
    }
}