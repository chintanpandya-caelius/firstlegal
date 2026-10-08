@isTest
private class ActivityKPIControllerTest {

    @TestSetup
    static void makeData() {
        String seed = String.valueOf(Datetime.now().getTime());

        // 1. Create Active Goal
        KPI_Goal__c activeGoal = new KPI_Goal__c(
            User__c = UserInfo.getUserId(),
            Reporting_Period__c = 'Monthly',
            Active__c = true,
            Email_Goal__c = 10,
            Call_Goal__c = 10,
            Task_Goal__c = 10,
            Event_Goal__c = 10,
            Effective_From__c = Date.today().addDays(-10),
            Effective_To__c = Date.today().addDays(10)
        );
        insert activeGoal;

        // 2. Configure DML options to pass duplicate rules
        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        dmlOpts.DuplicateRuleHeader.allowSave = true;

        // Create Account
        Account acc = new Account(
            Name = 'Test Account KPI ' + seed,
            BillingStreet = '123 Main St ' + seed,
            BillingCity = 'San Francisco',
            BillingState = 'California',
            BillingPostalCode = '94105',
            BillingCountry = 'United States',
            ShippingStreet = '123 Main St ' + seed,
            ShippingCity = 'San Francisco',
            ShippingState = 'California',
            ShippingPostalCode = '94105',
            ShippingCountry = 'United States'
        );
        Database.insert(acc, dmlOpts);

        // Create Contact
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact ' + seed,
            AccountId = acc.Id,
            Email = 'test' + seed + '@example.com',
            MailingStreet = '123 Main St ' + seed,
            MailingCity = 'San Francisco',
            MailingState = 'California',
            MailingPostalCode = '94105',
            MailingCountry = 'United States'
        );
        Database.insert(con, dmlOpts);

        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opp ' + seed,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acc.Id
            
        );
        insert opp;

        // Create Lead
        Lead ld = new Lead(
            FirstName = 'Test',
            LastName = 'Lead ' + seed,
            Company = 'Company ' + seed,
            Email = 'lead' + seed + '@example.com',
            SLA__c = 'S1'
        );
        insert ld;

        // 3. Create Tasks
        Task callTask = new Task(
            Subject = 'Call Task ' + seed,
            TaskSubtype = 'Call',
            WhatId = acc.Id,
            ActivityDate = Date.today()
        );

        Task regularTask = new Task(
            Subject = 'Regular Task ' + seed,
            WhatId = acc.Id,
            ActivityDate = Date.today()
        );

        insert new List<Task>{callTask, regularTask};

        // 4. Create Events
        Event virtualEvt = new Event(
            Subject = 'Virtual Meeting ' + seed,
            Type = 'Meeting',
            Event_Type__c = 'Meeting',
            Event_Subtype__c = 'Virtual Meeting',
            WhatId = acc.Id,
            StartDateTime = Datetime.now(),
            EndDateTime = Datetime.now().addHours(1),
            ActivityDate = Date.today()
        );

        Event inPersonEvt = new Event(
            Subject = 'In Person Meeting ' + seed,
            Type = 'Meeting',
            Event_Type__c = 'Meeting',
            Event_Subtype__c = 'In Person Meeting',
            WhatId = acc.Id,
            StartDateTime = Datetime.now(),
            EndDateTime = Datetime.now().addHours(1),
            ActivityDate = Date.today()
        );

        insert new List<Event>{virtualEvt, inPersonEvt};

        // 5. Create Email Message
        EmailMessage emailMsg = new EmailMessage(
            Subject = 'Test Email ' + seed,
            RelatedToId = acc.Id,
            Status = '3'
        );
        insert emailMsg;
    }

    @isTest
    static void testGetMyKPIGlobalContext() {
        Test.startTest();

        ActivityKPIController.KPIResponse response =
            ActivityKPIController.getMyKPI(null, 'Monthly');

        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(
            'Monthly',
            response.reportingPeriod,
            'Reporting period should match requested value'
        );
        System.assertEquals(
            5,
            response.kpiRows.size(),
            'Should return 5 KPI Rows'
        );

        for (ActivityKPIController.KPIRow row : response.kpiRows) {
            if (row.activityType == 'Events') {
                System.assertEquals(true, row.isEventTile);
            }

            if (row.activityType == 'TOTAL') {
                System.assertEquals(40, row.targetGoal);
            }
        }
    }

    @isTest
    static void testGetMyKPIAccountContext() {
        List<Account> accList = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        System.assert(
            !accList.isEmpty(),
            'Account test data must exist'
        );

        Test.startTest();

        ActivityKPIController.KPIResponse response =
            ActivityKPIController.getMyKPI(
                accList[0].Id,
                'Monthly'
            );

        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(5, response.kpiRows.size());
    }

    @isTest
    static void testGetMyKPINonAccountContextAndNullPeriod() {
        List<Contact> conList = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        System.assert(
            !conList.isEmpty(),
            'Contact test data must exist'
        );

        Test.startTest();

        ActivityKPIController.KPIResponse response =
            ActivityKPIController.getMyKPI(
                conList[0].Id,
                null
            );

        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(
            'Monthly',
            response.reportingPeriod
        );
    }

    @isTest
    static void testGetMyKPINoActiveGoals() {
        List<KPI_Goal__c> goals = [
            SELECT Id, Active__c
            FROM KPI_Goal__c
        ];

        for (KPI_Goal__c g : goals) {
            g.Active__c = false;
        }

        update goals;

        Test.startTest();

        ActivityKPIController.KPIResponse response =
            ActivityKPIController.getMyKPI(
                null,
                'Quarterly'
            );

        Test.stopTest();

        System.assertEquals(
            'Quarterly',
            response.reportingPeriod
        );
        System.assertEquals(
            0,
            response.kpiRows[0].targetGoal
        );
        System.assertEquals(
            'No Target Set',
            response.kpiRows[0].statusLabel
        );
        System.assertEquals(
            'slds-text-color_weak',
            response.kpiRows[0].statusClass
        );
    }

    @isTest
    static void testKPIRowConstructorsAndThresholds() {
        Test.startTest();

        ActivityKPIController.KPIRow simpleRow =
            new ActivityKPIController.KPIRow(
                'TestType',
                5,
                10,
                20
            );

        System.assertEquals(
            'TestType',
            simpleRow.activityType
        );
        System.assertEquals(
            5,
            simpleRow.currentTouchPoints
        );

        // Status Thresholds
        ActivityKPIController.KPIRow rowMet =
            new ActivityKPIController.KPIRow(
                'Test',
                10,
                10,
                10
            );

        System.assertEquals(
            'Target Met',
            rowMet.statusLabel
        );

        ActivityKPIController.KPIRow rowTrack =
            new ActivityKPIController.KPIRow(
                'Test',
                8,
                10,
                8
            );

        System.assertEquals(
            'On Track',
            rowTrack.statusLabel
        );

        ActivityKPIController.KPIRow rowAttention =
            new ActivityKPIController.KPIRow(
                'Test',
                6,
                10,
                6
            );

        System.assertEquals(
            'Needs Attention',
            rowAttention.statusLabel
        );

        ActivityKPIController.KPIRow rowBehind =
            new ActivityKPIController.KPIRow(
                'Test',
                2,
                10,
                2
            );

        System.assertEquals(
            'Behind Target',
            rowBehind.statusLabel
        );

        Test.stopTest();
    }
}