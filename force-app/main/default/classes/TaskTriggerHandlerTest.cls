@IsTest
private class TaskTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        insert new List<Case>{
            new Case(
                Subject = 'Closed Case',
                Status = 'Closed',
                Origin = 'Email',
                Open_Task_Count__c = 0
            ),
            new Case(
                Subject = 'Resolved Case',
                Status = 'Resolved',
                Origin = 'Email',
                Open_Task_Count__c = 0
            ),
            new Case(
                Subject = 'Open Case',
                Status = 'New',
                Origin = 'Email',
                Open_Task_Count__c = 0
            ),
            new Case(
                Subject = 'Delete Case',
                Status = 'New',
                Origin = 'Email',
                Open_Task_Count__c = 0
            )
        };
    }

    @IsTest
    static void testClosedAndResolvedCases() {
        Case closedCase = [
            SELECT Id, Open_Task_Count__c
            FROM Case
            WHERE Subject = 'Closed Case'
            LIMIT 1
        ];

        Case resolvedCase = [
            SELECT Id, Open_Task_Count__c
            FROM Case
            WHERE Subject = 'Resolved Case'
            LIMIT 1
        ];

        Task closedTask = new Task(
            WhatId = closedCase.Id,
            Status = 'Not Started',
            Subject = 'Closed Case Task'
        );

        Task resolvedTask = new Task(
            WhatId = resolvedCase.Id,
            Status = 'Not Started',
            Subject = 'Resolved Case Task'
        );

        Test.startTest();

        TaskTriggerHandler.handle(
            new List<Task>{ closedTask },
            null,
            false
        );

        TaskTriggerHandler.handle(
            new List<Task>{ resolvedTask },
            null,
            false
        );

        Test.stopTest();

        System.assertEquals(true, closedTask.hasErrors());
        System.assertEquals(true, resolvedTask.hasErrors());

        closedCase = [
            SELECT Open_Task_Count__c
            FROM Case
            WHERE Id = :closedCase.Id
        ];

        resolvedCase = [
            SELECT Open_Task_Count__c
            FROM Case
            WHERE Id = :resolvedCase.Id
        ];

        System.assertEquals(1, closedCase.Open_Task_Count__c);
        System.assertEquals(1, resolvedCase.Open_Task_Count__c);
    }

    @IsTest
    static void testReopeningTaskOnClosedCase() {
        Case openCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Open Case'
            LIMIT 1
        ];

        Case closedCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Closed Case'
            LIMIT 1
        ];

        Task realTask = new Task(
            WhatId = openCase.Id,
            Status = 'Not Started',
            Subject = 'Existing Task'
        );

        insert realTask;

        Task oldTask = new Task(
            Id = realTask.Id,
            WhatId = closedCase.Id,
            Status = 'Closed',
            Subject = 'Reopening Task'
        );

        Task newTask = new Task(
            Id = realTask.Id,
            WhatId = closedCase.Id,
            Status = 'Not Started',
            Subject = 'Reopening Task'
        );

        Test.startTest();

        TaskTriggerHandler.handle(
            new List<Task>{ newTask },
            new Map<Id, Task>{
                realTask.Id => oldTask
            },
            false
        );

        Test.stopTest();

        System.assertEquals(true, newTask.hasErrors());
    }

    @IsTest
    static void testOpenTaskInsertAndNullStatus() {
        Case openCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Open Case'
            LIMIT 1
        ];

        Task task = new Task(
            WhatId = openCase.Id,
            Status = 'Not Started',
            Subject = 'Open Task'
        );

        insert task;

        update new Case(
            Id = openCase.Id,
            Open_Task_Count__c = 0
        );

        Task nullStatusTask = new Task(
            WhatId = openCase.Id,
            Subject = 'Null Status Task'
        );

        Test.startTest();

        TaskTriggerHandler.handle(
            new List<Task>{ task, nullStatusTask },
            null,
            false
        );

        Test.stopTest();

        Case result = [
            SELECT Open_Task_Count__c
            FROM Case
            WHERE Id = :openCase.Id
        ];

        System.assertEquals(1, result.Open_Task_Count__c);
        System.assertEquals(false, task.hasErrors());
    }

    @IsTest
    static void testTaskUpdateCloseAndReopen() {
        Case openCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Open Case'
            LIMIT 1
        ];

        Task task = new Task(
            WhatId = openCase.Id,
            Status = 'Not Started',
            Subject = 'Update Task'
        );

        insert task;

        update new Case(
            Id = openCase.Id,
            Open_Task_Count__c = 1
        );

        Task oldOpenTask = new Task(
            Id = task.Id,
            WhatId = openCase.Id,
            Status = 'Not Started',
            Subject = 'Update Task'
        );

        task.Status = 'Completed';

        Test.startTest();

        TaskTriggerHandler.handle(
            new List<Task>{ task },
            new Map<Id, Task>{
                task.Id => oldOpenTask
            },
            false
        );

        Test.stopTest();

        Case result = [
            SELECT Open_Task_Count__c
            FROM Case
            WHERE Id = :openCase.Id
        ];

        System.assertEquals(0, result.Open_Task_Count__c);

        update new Case(
            Id = openCase.Id,
            Open_Task_Count__c = 0
        );

        Task oldClosedTask = new Task(
            Id = task.Id,
            WhatId = openCase.Id,
            Status = 'Completed',
            Subject = 'Update Task'
        );

        task.Status = 'Not Started';

        TaskTriggerHandler.handle(
            new List<Task>{ task },
            new Map<Id, Task>{
                task.Id => oldClosedTask
            },
            false
        );

        result = [
            SELECT Open_Task_Count__c
            FROM Case
            WHERE Id = :openCase.Id
        ];
    }

    @IsTest
    static void testTaskDelete() {
        Case deleteCase = [
            SELECT Id
            FROM Case
            WHERE Subject = 'Delete Case'
            LIMIT 1
        ];

        Task openTask1 = new Task(
            WhatId = deleteCase.Id,
            Status = 'Not Started',
            Subject = 'Open Task 1'
        );

        Task openTask2 = new Task(
            WhatId = deleteCase.Id,
            Status = 'In Progress',
            Subject = 'Open Task 2'
        );

        Task closedTask = new Task(
            WhatId = deleteCase.Id,
            Status = 'Completed',
            Subject = 'Closed Task'
        );

        insert new List<Task>{
            openTask1,
            openTask2,
            closedTask
        };

        update new Case(
            Id = deleteCase.Id,
            Open_Task_Count__c = 2
        );

        Test.startTest();

        TaskTriggerHandler.handle(
            null,
            new Map<Id, Task>{
                openTask1.Id => openTask1
            },
            true
        );

        Test.stopTest();

        Case result = [
            SELECT Open_Task_Count__c
            FROM Case
            WHERE Id = :deleteCase.Id
        ];
    }

    @IsTest
    static void testNoCaseRelatedTasks() {
        Account accountRecord = new Account(
            Name = 'Test Account'
        );

        insert accountRecord;

        Task accountTask = new Task(
            WhatId = accountRecord.Id,
            Status = 'Not Started',
            Subject = 'Account Task'
        );

        Task noRelatedRecordTask = new Task(
            Status = 'Not Started',
            Subject = 'No Related Record'
        );

        Test.startTest();

        TaskTriggerHandler.handle(
            new List<Task>{
                accountTask,
                noRelatedRecordTask
            },
            null,
            false
        );

        Test.stopTest();

        System.assertEquals(false, accountTask.hasErrors());
        System.assertEquals(false, noRelatedRecordTask.hasErrors());
    }

    @IsTest
    static void testExceptionPath() {
        Boolean exceptionThrown = false;

        try {
            Test.startTest();

            TaskTriggerHandler.handle(
                null,
                null,
                false
            );

            Test.stopTest();
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }
}