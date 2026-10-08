@IsTest
private class LeadSLABreachHandlerTest {

    /*
     * ============================================================
     * GET VALID LEAD CHANNEL
     * ============================================================
     */
    private static String getLeadChannelValue() {

        Schema.DescribeFieldResult fieldDescribe =
            Lead.Lead_Channel__c.getDescribe();

        for (Schema.PicklistEntry entry :
             fieldDescribe.getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


    /*
     * ============================================================
     * GET VALID CUSTOM LEAD SOURCE
     * ============================================================
     *
     * IMPORTANT:
     * Your validation rule checks Lead_Source__c,
     * NOT the standard LeadSource field.
     */
    private static String getLeadSourceValue() {

        Schema.DescribeFieldResult fieldDescribe =
            Lead.Lead_Source__c.getDescribe();

        for (Schema.PicklistEntry entry :
             fieldDescribe.getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


    /*
     * ============================================================
     * TEST DATA
     * ============================================================
     */
    @TestSetup
    static void createTestData() {

        String leadChannelValue = getLeadChannelValue();
        String leadSourceValue = getLeadSourceValue();

        System.assertNotEquals(
            null,
            leadChannelValue,
            'Lead Channel must have an active picklist value.'
        );

        System.assertNotEquals(
            null,
            leadSourceValue,
            'Lead Source must have an active picklist value.'
        );

        List<Lead> leads = new List<Lead>();

        for (Integer i = 0; i < 10; i++) {

            Lead lead = new Lead();

            /*
             * Required fields from Lead_Mandatory_Fields
             */
            lead.FirstName = 'SLA';
            lead.LastName = 'Test ' + i;
            lead.Company = 'SLA Test Company ' + i;
            lead.Email = 'sla.test.' + i + '@example.com';
            lead.Phone = '555' + String.valueOf(1000000 + i);
            lead.Title = 'SLA Test Lead';
            lead.PostalCode = '1000' + String.valueOf(i);

            /*
             * REQUIRED BY:
             * Require_Lead_Channel_And_Lead_Source
             *
             * IMPORTANT:
             * These are the CUSTOM fields from your validation rule.
             */
            lead.Lead_Channel__c = leadChannelValue;
            lead.Lead_Source__c = leadSourceValue;

            /*
             * SLA fields
             */
            lead.SLA_Breached__c = false;

            leads.add(lead);
        }

        insert leads;
    }


    /*
     * ============================================================
     * TEST 1
     * Overdue + incomplete Lead
     * ============================================================
     */
    @IsTest
    static void testOverdueIncompleteLead() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 0'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(-2);

        lead.SLA_Completion_Date__c = null;
        lead.SLA_Breached__c = false;

        Test.startTest();

        update lead;

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            true,
            result.SLA_Breached__c,
            'Overdue incomplete Lead should be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 2
     * Completed AFTER Due Date
     * ============================================================
     */
    @IsTest
    static void testCompletedAfterDueDate() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 1'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(-3);

        lead.SLA_Completion_Date__c =
            System.now().addHours(-1);

        lead.SLA_Breached__c = false;

        Test.startTest();

        update lead;

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            true,
            result.SLA_Breached__c,
            'Lead completed after Due Date should be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 3
     * Completed BEFORE Due Date
     * ============================================================
     */
    @IsTest
    static void testCompletedBeforeDueDate() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 2'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(3);

        lead.SLA_Completion_Date__c =
            System.now();

        lead.SLA_Breached__c = false;

        Test.startTest();

        update lead;

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'Lead completed before Due Date should not be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 4
     * Future Due Date
     * ============================================================
     */
    @IsTest
    static void testFutureDueDate() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 3'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(5);

        lead.SLA_Completion_Date__c = null;
        lead.SLA_Breached__c = false;

        Test.startTest();

        update lead;

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'Future SLA should not be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 5
     * No Due Date
     * ============================================================
     */
    @IsTest
    static void testNoDueDate() {

        Lead lead = [
            SELECT Id,
                   Company,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 4'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c = null;
        lead.SLA_Completion_Date__c = null;
        lead.Company = 'Updated Company';

        Test.startTest();

        update lead;

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'Lead without Due Date should not be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 6
     * Unrelated Update
     * ============================================================
     */
    @IsTest
    static void testUnrelatedUpdate() {

        Lead lead = [
            SELECT Id,
                   Company,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 5'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(5);

        lead.SLA_Completion_Date__c = null;
        lead.SLA_Breached__c = false;

        update lead;

        /*
         * Change only a normal business field.
         */
        lead.Company = 'Unrelated Company Update';

        Test.startTest();

        update lead;

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'Unrelated update should not change breach status.'
        );
    }


    /*
     * ============================================================
     * TEST 7
     * Scheduler - Overdue Incomplete
     * ============================================================
     */
    @IsTest
    static void testSchedulerOverdueIncompleteLead() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 6'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(-5);

        lead.SLA_Completion_Date__c = null;
        lead.SLA_Breached__c = false;

        update lead;

        Test.startTest();

        String jobId = System.schedule(
            'Test Lead SLA Breach Scheduler',
            '0 0 1 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Scheduler job should be created.'
        );

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            true,
            result.SLA_Breached__c,
            'Scheduler should breach overdue incomplete Lead.'
        );
    }


    /*
     * ============================================================
     * TEST 8
     * Scheduler - Late Completion
     * ============================================================
     */
    @IsTest
    static void testSchedulerLateCompletion() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 7'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(-5);

        lead.SLA_Completion_Date__c =
            System.now().addHours(-2);

        lead.SLA_Breached__c = false;

        update lead;

        Test.startTest();

        String jobId = System.schedule(
            'Test Lead SLA Late Completion Scheduler',
            '0 0 2 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Scheduler job should be created.'
        );

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            true,
            result.SLA_Breached__c,
            'Late completed Lead should be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 9
     * Scheduler - Future Lead
     * ============================================================
     */
    @IsTest
    static void testSchedulerFutureLead() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Test 8'
            LIMIT 1
        ];

        lead.SLA_Due_Date__c =
            System.now().addHours(10);

        lead.SLA_Completion_Date__c = null;
        lead.SLA_Breached__c = false;

        update lead;

        Test.startTest();

        String jobId = System.schedule(
            'Test Lead SLA Future Scheduler',
            '0 0 3 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'Scheduler job should be created.'
        );

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'Future SLA should not be breached.'
        );
    }


    /*
     * ============================================================
     * TEST 10
     * Bulk Processing
     * ============================================================
     */
    @IsTest
    static void testBulkProcessing() {

        List<Lead> leads = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName LIKE 'Test%'
            LIMIT 10
        ];

        System.assertEquals(
            10,
            leads.size(),
            '10 test Leads should exist.'
        );

        for (Lead lead : leads) {

            lead.SLA_Due_Date__c =
                System.now().addHours(-2);

            lead.SLA_Completion_Date__c = null;
            lead.SLA_Breached__c = false;
        }

        Test.startTest();

        update leads;

        Test.stopTest();

        List<Lead> results = [
            SELECT Id,
                   SLA_Breached__c
            FROM Lead
            WHERE Id IN :leads
        ];

        System.assertEquals(
            10,
            results.size(),
            'All 10 Leads should be processed.'
        );

        for (Lead lead : results) {

            System.assertEquals(
                true,
                lead.SLA_Breached__c,
                'Every overdue Lead should be breached.'
            );
        }
    }
}