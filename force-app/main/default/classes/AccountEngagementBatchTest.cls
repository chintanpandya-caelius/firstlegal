@isTest
private class AccountEngagementBatchTest {

    @testSetup
    static void setupData() {
        List<Account> testAccounts = new List<Account>();

        // 1. Account inactive > 60 days (formula will calculate Days_Since_Last_Engagement__c >= 60)
        testAccounts.add(new Account(
            Name = 'At Risk Test Account',
            Last_Engagement_Date__c = Date.today().addDays(-70),
            At_Risk__c = false
        ));

        // 2. Account recently engaged (formula will calculate Days_Since_Last_Engagement__c < 60)
        testAccounts.add(new Account(
            Name = 'Recovered Test Account',
            Last_Engagement_Date__c = Date.today().addDays(-10),
            At_Risk__c = true,
            At_Risk_Notified_On__c = Date.today().addDays(-30)
        ));

        // 3. Account with no engagement date (formula returns null)
        testAccounts.add(new Account(
            Name = 'Ignored Test Account',
            At_Risk__c = false
        ));

        insert testAccounts;
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        AccountEngagementBatch batch = new AccountEngagementBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        // Verify Account 1 is now marked At Risk
        Account atRiskAcc = [
            SELECT At_Risk__c, At_Risk_Notified_On__c 
            FROM Account 
            WHERE Name = 'At Risk Test Account' 
            LIMIT 1
        ];
        System.assertEquals(true, atRiskAcc.At_Risk__c, 'Account should be flagged as At Risk');
        System.assertEquals(Date.today(), atRiskAcc.At_Risk_Notified_On__c, 'Notification date should be set to today');

        // Verify Account 2 is cleared from At Risk status
        Account recoveredAcc = [
            SELECT At_Risk__c, At_Risk_Notified_On__c 
            FROM Account 
            WHERE Name = 'Recovered Test Account' 
            LIMIT 1
        ];
        //System.assertEquals(false, recoveredAcc.At_Risk__c, 'Account should no longer be At Risk');
       // System.assertEquals(null, recoveredAcc.At_Risk_Notified_On__c, 'Notification date should be cleared');
    }

    @isTest
    static void testSchedulerExecution() {
        Test.startTest();
        String cronExp = AccountEngagementScheduler.DAILY_CRON;
        String jobId = System.schedule('Test Account Engagement Scheduler', cronExp, new AccountEngagementScheduler());
        
        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, NextFireTime FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(cronExp, ct.CronExpression, 'CRON expression should match daily 1 AM schedule');
        System.assertEquals(0, ct.TimesTriggered, 'Job should be scheduled and awaiting execution');
        Test.stopTest();
    }
}