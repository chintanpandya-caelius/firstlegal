/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Scheduler class to schedule QuarterlyAccountReviewBatch, and AccountInactivityTaskCreationBatch
* @Story Number : 5450
*/

global class AccountAutomationScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        AccountAutomationConfig config = AccountAutomationConfig.getConfig();

        if (config.quarterlyReviewEnabled) {
            Database.executeBatch(new QuarterlyAccountReviewBatch(), 200);
        }

        if (config.inactivityMonitoringEnabled) {
            Database.executeBatch(new AccountInactivityTaskCreationBatch(), 200);
        }
    }
}