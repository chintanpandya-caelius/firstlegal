@IsTest
private class LeadSLABreachSchedulerTest {

    private static String getLeadChannelValue() {

        for (Schema.PicklistEntry entry :
             Lead.Lead_Channel__c.getDescribe().getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


   
    private static String getLeadSourceValue() {

        for (Schema.PicklistEntry entry :
             Lead.Lead_Source__c.getDescribe().getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        return null;
    }


 
    @TestSetup
    static void createTestData() {

        String leadChannelValue = getLeadChannelValue();
        String leadSourceValue = getLeadSourceValue();

        System.assertNotEquals(
            null,
            leadChannelValue,
            'Lead Channel must have an active value.'
        );

        System.assertNotEquals(
            null,
            leadSourceValue,
            'Lead Source must have an active value.'
        );

        List<Lead> leads = new List<Lead>();
         
        Lead overdueIncomplete = new Lead(
            FirstName = 'SLA',
            LastName = 'Scheduler Overdue',
            Company = 'SLA Scheduler Test',
            Email = 'scheduler.overdue@example.com',
            Phone = '5551000001',
            Title = 'SLA Test',
            PostalCode = '10001',
            Lead_Channel__c = leadChannelValue,
            Lead_Source__c = leadSourceValue,
            SLA_Due_Date__c = System.now().addHours(-5),
            SLA_Completion_Date__c = null,
            SLA_Breached__c = false,
            SLA_Breach_Notified__c = false
        );

        leads.add(overdueIncomplete);



        Lead completedLate = new Lead(
            FirstName = 'SLA',
            LastName = 'Scheduler Late',
            Company = 'SLA Scheduler Test',
            Email = 'scheduler.late@example.com',
            Phone = '5551000002',
            Title = 'SLA Test',
            PostalCode = '10002',
            Lead_Channel__c = leadChannelValue,
            Lead_Source__c = leadSourceValue,
            SLA_Due_Date__c = System.now().addHours(-5),
            SLA_Completion_Date__c = System.now().addHours(-2),
            SLA_Breached__c = false,
            SLA_Breach_Notified__c = false
        );

        leads.add(completedLate);


        Lead futureLead = new Lead(
            FirstName = 'SLA',
            LastName = 'Scheduler Future',
            Company = 'SLA Scheduler Test',
            Email = 'scheduler.future@example.com',
            Phone = '5551000003',
            Title = 'SLA Test',
            PostalCode = '10003',
            Lead_Channel__c = leadChannelValue,
            Lead_Source__c = leadSourceValue,
            SLA_Due_Date__c = System.now().addHours(5),
            SLA_Completion_Date__c = null,
            SLA_Breached__c = false,
            SLA_Breach_Notified__c = false
        );

        leads.add(futureLead);


        
        Lead noDueDate = new Lead(
            FirstName = 'SLA',
            LastName = 'Scheduler No Due Date',
            Company = 'SLA Scheduler Test',
            Email = 'scheduler.nodue@example.com',
            Phone = '5551000004',
            Title = 'SLA Test',
            PostalCode = '10004',
            Lead_Channel__c = leadChannelValue,
            Lead_Source__c = leadSourceValue,
            SLA_Due_Date__c = null,
            SLA_Completion_Date__c = null,
            SLA_Breached__c = false,
            SLA_Breach_Notified__c = false
        );

        leads.add(noDueDate);


        insert leads;
    }



    @IsTest
    static void testSchedulerExecution() {

        Test.startTest();

        String jobId = System.schedule(
            'Lead SLA Breach Scheduler Test',
            '0 0 1 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId,
            'The Lead SLA Breach Scheduler should be scheduled successfully.'
        );
    }


  
    @IsTest
    static void testOverdueIncompleteLead() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Scheduler Overdue'
            LIMIT 1
        ];

        Test.startTest();

        System.schedule(
            'Lead SLA Overdue Test',
            '0 0 2 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            true,
            result.SLA_Breached__c,
            'An overdue incomplete Lead should be marked as breached.'
        );
    }


  
    @IsTest
    static void testCompletedLate() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Scheduler Late'
            LIMIT 1
        ];

        Test.startTest();

        System.schedule(
            'Lead SLA Late Completion Test',
            '0 0 3 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        
    }



    @IsTest
    static void testFutureDueDate() {

        Lead lead = [
            SELECT Id,
                   SLA_Due_Date__c,
                   SLA_Completion_Date__c,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Scheduler Future'
            LIMIT 1
        ];

        Test.startTest();

        System.schedule(
            'Lead SLA Future Test',
            '0 0 4 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'A Lead whose Due Date is in the future should not be breached.'
        );
    }


   
    @IsTest
    static void testNoDueDate() {

        Lead lead = [
            SELECT Id,
                   SLA_Breached__c
            FROM Lead
            WHERE LastName = 'Scheduler No Due Date'
            LIMIT 1
        ];

        Test.startTest();

        System.schedule(
            'Lead SLA No Due Date Test',
            '0 0 5 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        Lead result = [
            SELECT SLA_Breached__c
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            false,
            result.SLA_Breached__c,
            'A Lead without an SLA Due Date should not be breached.'
        );
    }



    @IsTest
    static void testBulkSchedulerProcessing() {

        String leadChannelValue = getLeadChannelValue();
        String leadSourceValue = getLeadSourceValue();

        List<Lead> leads = new List<Lead>();

        for (Integer i = 0; i < 20; i++) {

            leads.add(new Lead(
                FirstName = 'Bulk',
                LastName = 'SLA ' + i,
                Company = 'Bulk SLA Test',
                Email = 'bulk.sla.' + i + '@example.com',
                Phone = '555' + String.valueOf(3000000 + i),
                Title = 'SLA Test',
                PostalCode = '2000' + String.valueOf(i),
                Lead_Channel__c = leadChannelValue,
                Lead_Source__c = leadSourceValue,
                SLA_Due_Date__c = System.now().addHours(-4),
                SLA_Completion_Date__c = null,
                SLA_Breached__c = false,
                SLA_Breach_Notified__c = false
            ));
        }

        insert leads;

        Test.startTest();

        System.schedule(
            'Lead SLA Bulk Scheduler Test',
            '0 0 6 1 12 ? 2099',
            new LeadSLABreachScheduler()
        );

        Test.stopTest();

        List<Lead> results = [
            SELECT Id,
                   SLA_Breached__c
            FROM Lead
            WHERE Id IN :leads
        ];

        System.assertEquals(
            20,
            results.size(),
            'All 20 test Leads should exist.'
        );

        for (Lead lead : results) {

            System.assertEquals(
                true,
                lead.SLA_Breached__c,
                'Every overdue Lead should be marked as breached.'
            );
        }
    }
}