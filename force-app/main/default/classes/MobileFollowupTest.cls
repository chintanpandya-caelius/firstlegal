@IsTest
private class MobileFollowupTest {
    // The two activity fields are new; the running test user's profile has no field-level
    // security on them (FLS is granted by PS_Mobile_Activity_Actions in package 02).
    // DML and SOQL touching those fields therefore run explicitly in system mode.

    @IsTest static void mobileCallsDoNotCreateAutomaticFollowups() {
        List<Task> calls = new List<Task>();
        for (Integer i = 0; i < 200; i++) {
            calls.add(new Task(Subject = 'Mobile call ' + i, Status = 'Completed', Priority = 'Normal',
                TaskSubtype = 'Call', Engagement_Type__c = 'Conversation', Manual_Followup__c = true));
        }
        Test.startTest();
        insert as system calls;
        Test.stopTest();
        System.assertEquals(0, [SELECT count() FROM Task WHERE Subject = 'Follow-up Call' WITH SYSTEM_MODE]);
        System.assertEquals(200, [SELECT count() FROM Task WHERE Manual_Followup__c = true WITH SYSTEM_MODE]);
    }

    @IsTest static void legacyCallsKeepTheirExistingAutomaticFollowup() {
        Task legacy = new Task(Subject = 'Test legacy call', Status = 'Completed', Priority = 'Normal', TaskSubtype = 'Call');
        Test.startTest();
        insert as system legacy;
        Test.stopTest();
        List<Task> followups = [SELECT Subject, Status, Priority, ActivityDate, OwnerId FROM Task
                                WHERE Subject = 'Follow-up Call' WITH SYSTEM_MODE];
        System.assertEquals(1, followups.size());
        System.assertEquals('Not Started', followups[0].Status);
        System.assertEquals('Normal', followups[0].Priority);
        System.assertEquals(Date.today().addDays(2), followups[0].ActivityDate);
        System.assertEquals(UserInfo.getUserId(), followups[0].OwnerId);
    }

    @IsTest static void mixedBatchOnlyCreatesLegacyFollowup() {
        List<Task> batch = new List<Task>{
            new Task(Subject = 'Test manual', Status = 'Completed', Priority = 'Normal', TaskSubtype = 'Call',
                Manual_Followup__c = true, Engagement_Type__c = 'Birthday'),
            new Task(Subject = 'Test legacy', Status = 'Completed', Priority = 'Normal', TaskSubtype = 'Call'),
            new Task(Subject = 'Test ordinary', Status = 'Not Started', Priority = 'Normal')
        };
        Test.startTest();
        insert as system batch;
        Test.stopTest();
        System.assertEquals(1, [SELECT count() FROM Task WHERE Subject = 'Follow-up Call' WITH SYSTEM_MODE]);
    }
}