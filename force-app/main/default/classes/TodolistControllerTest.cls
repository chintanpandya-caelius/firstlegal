@IsTest
private class TodolistControllerTest {

    private static User createTestUser(String uniqueValue) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User u = new User(
            FirstName = 'Activity',
            LastName = 'Persona ' + uniqueValue,
            Alias = 'act' + uniqueValue.substring(0, 5),
            Email = 'activitypersona' + uniqueValue + '@example.com',
            Username = 'activitypersona' + uniqueValue + '@example.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        insert u;
        return u;
    }

    @TestSetup
    static void setupData() {
        String seed = String.valueOf(Datetime.now().getTime());

        User currentUser = [
            SELECT Id
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        dmlOpts.DuplicateRuleHeader.allowSave = true;

        Account acc = new Account(
            Name = 'Activity Center Account ' + seed,
            BillingStreet = '123 Main Street',
            BillingCity = 'San Francisco',
            BillingState = 'California',
            BillingPostalCode = '94105',
            BillingCountry = 'United States',
            ShippingStreet = '123 Main Street',
            ShippingCity = 'San Francisco',
            ShippingState = 'California',
            ShippingPostalCode = '94105',
            ShippingCountry = 'United States'
        );

        Database.insert(acc, dmlOpts);

        Contact con = new Contact(
            FirstName = 'Activity',
            LastName = 'Contact ' + seed,
            AccountId = acc.Id,
            Email = 'activitycontact' + seed + '@example.com',
            MailingStreet = '123 Main Street',
            MailingCity = 'San Francisco',
            MailingState = 'California',
            MailingPostalCode = '94105',
            MailingCountry = 'United States'
        );

        Database.insert(con, dmlOpts);

        // Today's normal Task
        Task todayTask = new Task(
            OwnerId = currentUser.Id,
            Subject = 'Today Regular Task ' + seed,
            Status = 'Not Started',
            Priority = 'Normal',
            WhatId = acc.Id,
            WhoId = con.Id,
            ActivityDate = Date.today()
        );

        // Today's Call
        Task todayCall = new Task(
            OwnerId = currentUser.Id,
            Subject = 'Today Call ' + seed,
            Status = 'Not Started',
            Priority = 'High',
            TaskSubtype = 'Call',
            WhatId = acc.Id,
            WhoId = con.Id,
            ActivityDate = Date.today()
        );

        // Overdue normal Task
        Task overdueTask = new Task(
            OwnerId = currentUser.Id,
            Subject = 'Overdue Task ' + seed,
            Status = 'Not Started',
            Priority = 'Normal',
            WhatId = acc.Id,
            WhoId = con.Id,
            ActivityDate = Date.today().addDays(-3)
        );

        // Overdue Call
        Task overdueCall = new Task(
            OwnerId = currentUser.Id,
            Subject = 'Overdue Call ' + seed,
            Status = 'Not Started',
            Priority = 'High',
            TaskSubtype = 'Call',
            WhatId = acc.Id,
            WhoId = con.Id,
            ActivityDate = Date.today().addDays(-2)
        );

        insert new List<Task>{
            todayTask,
            todayCall,
            overdueTask,
            overdueCall
        };

        // Today's Meeting
        Datetime eventStart = Datetime.newInstance(
            Date.today(),
            Time.newInstance(10, 0, 0, 0)
        );

        Event todayEvent = new Event(
            OwnerId = currentUser.Id,
            Subject = 'Today Meeting ' + seed,
            Type = 'Meeting',
            WhatId = acc.Id,
            WhoId = con.Id,
            StartDateTime = eventStart,
            EndDateTime = eventStart.addHours(1)
        );

        insert todayEvent;

        // Today's Email
        EmailMessage emailMsg = new EmailMessage(
            Subject = 'Today Email ' + seed,
            RelatedToId = acc.Id,
            Status = '3',
            CreatedById = currentUser.Id
        );

        insert emailMsg;
    }

    @IsTest
    static void testGetActivityCenterData() {
        Test.startTest();

        TodolistController.ActivityDataWrapper wrapper =
            TodolistController.getActivityCenterData();

        Test.stopTest();

        System.assertNotEquals(
            null,
            wrapper,
            'Activity wrapper should not be null'
        );

        System.assertNotEquals(
            null,
            wrapper.todayActivities,
            'Today activities should not be null'
        );

        System.assertNotEquals(
            null,
            wrapper.overdueActivities,
            'Overdue activities should not be null'
        );

        System.assert(
            wrapper.todayActivities.size() >= 4,
            'Today activities should contain Task, Call, Meeting and Email'
        );

        System.assert(
            wrapper.overdueActivities.size() >= 2,
            'Overdue activities should contain overdue Task and Call'
        );

        Boolean foundTask = false;
        Boolean foundCall = false;
        Boolean foundMeeting = false;
        Boolean foundEmail = false;

        for (TodolistController.ActivityItem item :
             wrapper.todayActivities) {

            if (item.activityType == 'Task') {
                foundTask = true;

                System.assertEquals(
                    true,
                    item.isCompletable,
                    'Tasks should be completable'
                );

                System.assertEquals(
                    Date.today(),
                    item.dueDate,
                    'Today task should have today as due date'
                );
            }

            if (item.activityType == 'Call') {
                foundCall = true;

                System.assertEquals(
                    true,
                    item.isCompletable,
                    'Calls should be completable'
                );
            }

            if (item.activityType == 'Meeting') {
                foundMeeting = true;

                System.assertEquals(
                    false,
                    item.isCompletable,
                    'Meetings should not be completable'
                );

                System.assertEquals(
                    'Scheduled',
                    item.status
                );
            }

            if (item.activityType == 'Email') {
                foundEmail = true;

                System.assertEquals(
                    false,
                    item.isCompletable,
                    'Emails should not be completable'
                );

                System.assertEquals(
                    'Sent',
                    item.status
                );
            }
        }

        System.assertEquals(
            true,
            foundTask,
            'A Task should be returned for today'
        );

        System.assertEquals(
            true,
            foundCall,
            'A Call should be returned for today'
        );

        System.assertEquals(
            true,
            foundMeeting,
            'A Meeting should be returned for today'
        );

        System.assertEquals(
            true,
            foundEmail,
            'An Email should be returned for today'
        );
    }

    @IsTest
    static void testOverdueActivities() {
        Test.startTest();

        TodolistController.ActivityDataWrapper wrapper =
            TodolistController.getActivityCenterData();

        Test.stopTest();

        System.assertNotEquals(
            null,
            wrapper.overdueActivities
        );

        Boolean foundOverdueTask = false;
        Boolean foundOverdueCall = false;

        for (TodolistController.ActivityItem item :
             wrapper.overdueActivities) {

            System.assertEquals(
                true,
                item.isCompletable,
                'Overdue Tasks and Calls must be completable'
            );

            System.assertNotEquals(
                null,
                item.dueDate,
                'Overdue activity should have a due date'
            );

            System.assert(
                item.dueDate < Date.today(),
                'Overdue activity must have a date before today'
            );

            if (item.activityType == 'Task') {
                foundOverdueTask = true;
            }

            if (item.activityType == 'Call') {
                foundOverdueCall = true;
            }
        }

        System.assertEquals(
            true,
            foundOverdueTask,
            'Overdue Task should be returned'
        );

        System.assertEquals(
            true,
            foundOverdueCall,
            'Overdue Call should be returned'
        );
    }

    @IsTest
    static void testCompleteTask() {
        Task testTask = [
            SELECT Id, Status, OwnerId
            FROM Task
            WHERE Subject LIKE 'Today Regular Task%'
            LIMIT 1
        ];

        System.assertEquals(
            'Not Started',
            testTask.Status,
            'Test task should initially be open'
        );

        Test.startTest();

        TodolistController.completeTask(testTask.Id);

        Test.stopTest();

        Task updatedTask = [
            SELECT Id, Status
            FROM Task
            WHERE Id = :testTask.Id
        ];

        System.assertEquals(
            'Completed',
            updatedTask.Status,
            'completeTask should mark the task as Completed'
        );
    }

    @IsTest
    static void testCompleteCall() {
        Task callTask = [
            SELECT Id, Status, TaskSubtype
            FROM Task
            WHERE Subject LIKE 'Today Call%'
            LIMIT 1
        ];

        System.assertEquals(
            'Call',
            callTask.TaskSubtype,
            'Test record should be a Call'
        );

        Test.startTest();

        TodolistController.completeTask(callTask.Id);

        Test.stopTest();

        Task updatedCall = [
            SELECT Id, Status
            FROM Task
            WHERE Id = :callTask.Id
        ];

        System.assertEquals(
            'Completed',
            updatedCall.Status,
            'Call should be marked as Completed'
        );
    }

    @IsTest
    static void testActivityItemValues() {
        TodolistController.ActivityItem item =
            new TodolistController.ActivityItem();

        item.recordId = '001000000000001';
        item.recordLink = '/001000000000001';
        item.subject = 'Test Activity';
        item.activityType = 'Task';
        item.details = 'Test Account';
        item.status = 'Not Started';
        item.dueDate = Date.today();
        item.isCompletable = true;

        System.assertEquals(
            '001000000000001',
            item.recordId
        );

        System.assertEquals(
            '/001000000000001',
            item.recordLink
        );

        System.assertEquals(
            'Test Activity',
            item.subject
        );

        System.assertEquals(
            'Task',
            item.activityType
        );

        System.assertEquals(
            'Test Account',
            item.details
        );

        System.assertEquals(
            'Not Started',
            item.status
        );

        System.assertEquals(
            Date.today(),
            item.dueDate
        );

        System.assertEquals(
            true,
            item.isCompletable
        );
    }

    @IsTest
    static void testActivityDataWrapper() {
        TodolistController.ActivityDataWrapper wrapper =
            new TodolistController.ActivityDataWrapper();

        wrapper.todayActivities =
            new List<TodolistController.ActivityItem>();

        wrapper.overdueActivities =
            new List<TodolistController.ActivityItem>();

        System.assertNotEquals(
            null,
            wrapper.todayActivities
        );

        System.assertNotEquals(
            null,
            wrapper.overdueActivities
        );

        System.assertEquals(
            0,
            wrapper.todayActivities.size()
        );

        System.assertEquals(
            0,
            wrapper.overdueActivities.size()
        );
    }

    @IsTest
    static void testPersonaUserAccess() {
        String uniqueValue =
            String.valueOf(Datetime.now().getTime());

        User personaUser =
            createTestUser(uniqueValue);

        System.runAs(personaUser) {
            Test.startTest();

            TodolistController.ActivityDataWrapper wrapper =
                TodolistController.getActivityCenterData();

            Test.stopTest();

            System.assertNotEquals(
                null,
                wrapper,
                'Controller should execute for the persona user'
            );

            System.assertNotEquals(
                null,
                wrapper.todayActivities
            );

            System.assertNotEquals(
                null,
                wrapper.overdueActivities
            );
        }
    }

    @IsTest
    static void testNoDataForDifferentUser() {
        String uniqueValue =
            String.valueOf(Datetime.now().getTime());

        User anotherUser =
            createTestUser(uniqueValue);

        System.runAs(anotherUser) {
            Test.startTest();

            TodolistController.ActivityDataWrapper wrapper =
                TodolistController.getActivityCenterData();

            Test.stopTest();

            System.assertNotEquals(
                null,
                wrapper,
                'Wrapper should still be returned'
            );

            System.assertNotEquals(
                null,
                wrapper.todayActivities
            );

            System.assertNotEquals(
                null,
                wrapper.overdueActivities
            );
        }
    }
}