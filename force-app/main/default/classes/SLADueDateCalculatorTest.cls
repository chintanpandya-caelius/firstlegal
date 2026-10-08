@IsTest
private class SLADueDateCalculatorTest {

    // ============================================================
    // TEST SETUP
    // ============================================================
    @TestSetup
    static void setupTestData() {

        // --------------------------------------------------------
        // ACCOUNT
        // --------------------------------------------------------
        Account testAccount = new Account(
            Name = 'SLA Test Account'
        );
        insert testAccount;


        // --------------------------------------------------------
        // OPPORTUNITY
        // --------------------------------------------------------
        Opportunity testOpportunity = new Opportunity(
            Name = 'SLA Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpportunity;


        // --------------------------------------------------------
        // LEADS
        // --------------------------------------------------------
        List<Lead> testLeads = new List<Lead>();

        for (Integer i = 1; i <= 5; i++) {

            testLeads.add(new Lead(
                FirstName = 'Test' + i,
                LastName = 'Lead' + i,
                Company = 'SLA Test Company ' + i,
                Email = 'testlead' + i + '@example.com',
                Phone = '98765432' + String.valueOf(i),
                Title = 'Test Manager',
                PostalCode = '147001',

                // Standard Salesforce Lead Source
                LeadSource = 'Web',

                // Custom fields required by validation rules
                // Lead_Channel__c has valid value Web
                Lead_Channel__c = 'Web',

                // IMPORTANT:
                // 'Web' is NOT valid for Lead_Source__c.
                // 'Client' is a valid value from your screenshot.
                Lead_Source__c = 'Client'
            ));
        }

        insert testLeads;


        // --------------------------------------------------------
        // CONTACT
        // Used for unsupported object testing
        // --------------------------------------------------------
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Unsupported Contact',
            AccountId = testAccount.Id
        );
        insert testContact;
    }


    // ============================================================
    // HELPER METHOD - GET DEFAULT BUSINESS HOURS
    // ============================================================
    private static Id getBusinessHoursId() {

        List<BusinessHours> businessHoursList = [
            SELECT Id
            FROM BusinessHours
            WHERE IsDefault = true
            LIMIT 1
        ];

        System.assert(
            !businessHoursList.isEmpty(),
            'Default Business Hours must exist.'
        );

        return businessHoursList[0].Id;
    }


    // ============================================================
    // HELPER METHOD - CREATE SLA REQUEST
    // ============================================================
    private static SLADueDateCalculator.SLARequest createRequest(
        Id recordId,
        Id businessHoursId,
        Datetime recordDateTime,
        String slaTier,
        String calculationMode
    ) {

        SLADueDateCalculator.SLARequest request =
            new SLADueDateCalculator.SLARequest();

        request.recordId = recordId;
        request.businessHoursId = businessHoursId;
        request.recordDateTime = recordDateTime;
        request.slaTier = slaTier;
        request.calculationMode = calculationMode;

        return request;
    }


    // ============================================================
    // TEST NULL REQUESTS
    // ============================================================
    @IsTest
    static void testNullRequests() {

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(null);

        Test.stopTest();

        System.assertNotEquals(
            null,
            responses,
            'Response list should not be null.'
        );

        System.assertEquals(
            0,
            responses.size(),
            'Response list should be empty.'
        );
    }


    // ============================================================
    // TEST EMPTY REQUESTS
    // ============================================================
    @IsTest
    static void testEmptyRequests() {

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>()
            );

        Test.stopTest();

        System.assertNotEquals(null, responses);
        System.assertEquals(0, responses.size());
    }


    // ============================================================
    // TEST LEAD S1 INITIALIZE
    // ============================================================
    @IsTest
    static void testLeadS1Initialize() {

        Lead testLead = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testLead.Id,
                getBusinessHoursId(),
                System.now(),
                'S1',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{
                    request
                }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('SUCCESS', responses[0].status);
        System.assertNotEquals(null, responses[0].slaStartDate);
        System.assertNotEquals(null, responses[0].slaDueDate);
    }


    // ============================================================
    // TEST LEAD MULTIPLE TIERS
    // ============================================================
    @IsTest
    static void testLeadMultipleTiers() {

        List<Lead> leads = [
            SELECT Id
            FROM Lead
            LIMIT 3
        ];

        Id businessHoursId = getBusinessHoursId();

        List<SLADueDateCalculator.SLARequest> requests =
            new List<SLADueDateCalculator.SLARequest>{
                createRequest(
                    leads[0].Id,
                    businessHoursId,
                    System.now(),
                    'S2',
                    'INITIALIZE'
                ),
                createRequest(
                    leads[1].Id,
                    businessHoursId,
                    System.now(),
                    'S3',
                    'INITIALIZE'
                ),
                createRequest(
                    leads[2].Id,
                    businessHoursId,
                    System.now(),
                    'S4',
                    'INITIALIZE'
                )
            };

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(requests);

        Test.stopTest();

        System.assertEquals(3, responses.size());

        for (SLADueDateCalculator.SLAResponse response : responses) {

            System.assertEquals(
                'SUCCESS',
                response.status
            );

            System.assertNotEquals(
                null,
                response.slaStartDate
            );

            System.assertNotEquals(
                null,
                response.slaDueDate
            );
        }
    }


    // ============================================================
    // TEST ACCOUNT S1
    // ============================================================
    @IsTest
    static void testAccountS1() {

        Account testAccount = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testAccount.Id,
                getBusinessHoursId(),
                System.now(),
                'S1',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('SUCCESS', responses[0].status);
        System.assertNotEquals(null, responses[0].slaDueDate);
    }


    // ============================================================
    // TEST ACCOUNT S2
    // ============================================================
    @IsTest
    static void testAccountS2() {

        Account testAccount = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testAccount.Id,
                getBusinessHoursId(),
                System.now(),
                'S2',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('SUCCESS', responses[0].status);
        System.assertNotEquals(null, responses[0].slaDueDate);
    }


    // ============================================================
    // TEST OPPORTUNITY SLA
    // ============================================================
    @IsTest
    static void testOpportunitySLA() {

        Opportunity testOpportunity = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testOpportunity.Id,
                getBusinessHoursId(),
                System.now(),
                'S3',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('SUCCESS', responses[0].status);
        System.assertNotEquals(null, responses[0].slaDueDate);
    }


    // ============================================================
    // TEST MISSING RECORD ID
    // ============================================================
    @IsTest
    static void testMissingRecordId() {

        SLADueDateCalculator.SLARequest request =
            createRequest(
                null,
                getBusinessHoursId(),
                System.now(),
                'S1',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST MISSING BUSINESS HOURS ID
    // ============================================================
    @IsTest
    static void testMissingBusinessHoursId() {

        Account testAccount = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testAccount.Id,
                null,
                System.now(),
                'S1',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST MISSING SLA TIER
    // ============================================================
    @IsTest
    static void testMissingSLATier() {

        Lead testLead = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testLead.Id,
                getBusinessHoursId(),
                System.now(),
                null,
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST INVALID ACCOUNT TIER
    // ============================================================
    @IsTest
    static void testInvalidAccountTier() {

        Account testAccount = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testAccount.Id,
                getBusinessHoursId(),
                System.now(),
                'S3',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST INVALID LEAD TIER
    // ============================================================
    @IsTest
    static void testInvalidLeadTier() {

        Lead testLead = [
            SELECT Id
            FROM Lead
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testLead.Id,
                getBusinessHoursId(),
                System.now(),
                'INVALID',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST UNSUPPORTED OBJECT
    // ============================================================
    @IsTest
    static void testUnsupportedObject() {

        Contact testContact = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testContact.Id,
                getBusinessHoursId(),
                System.now(),
                'S1',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST BUSINESS HOURS NOT FOUND
    // ============================================================
    @IsTest
    static void testBusinessHoursNotFound() {

        Account testAccount = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        // BusinessHours Id prefix = 01m
        Id fakeBusinessHoursId =
            (Id) '01m000000000001AAA';

        SLADueDateCalculator.SLARequest request =
            createRequest(
                testAccount.Id,
                fakeBusinessHoursId,
                System.now(),
                'S1',
                'INITIALIZE'
            );

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(
                new List<SLADueDateCalculator.SLARequest>{ request }
            );

        Test.stopTest();

        System.assertEquals(1, responses.size());
        System.assertEquals('ERROR', responses[0].status);
    }


    // ============================================================
    // TEST BULK PROCESSING
    // ============================================================
    @IsTest
    static void testBulkProcessing() {

        List<Lead> leads = [
            SELECT Id
            FROM Lead
        ];

        Id businessHoursId = getBusinessHoursId();

        List<SLADueDateCalculator.SLARequest> requests =
            new List<SLADueDateCalculator.SLARequest>();

        for (Lead leadRecord : leads) {

            requests.add(
                createRequest(
                    leadRecord.Id,
                    businessHoursId,
                    System.now(),
                    'S1',
                    'INITIALIZE'
                )
            );
        }

        Test.startTest();

        List<SLADueDateCalculator.SLAResponse> responses =
            SLADueDateCalculator.calculateAndUpdate(requests);

        Test.stopTest();

        System.assertEquals(
            leads.size(),
            responses.size()
        );

        for (SLADueDateCalculator.SLAResponse response : responses) {

            System.assertEquals(
                'SUCCESS',
                response.status
            );

            System.assertNotEquals(
                null,
                response.slaDueDate
            );
        }
    }
}