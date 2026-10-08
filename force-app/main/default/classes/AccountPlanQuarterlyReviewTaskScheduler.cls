public with sharing class AccountPlanQuarterlyReviewTaskScheduler implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        Date today = System.today();
        
        if (AccountPlanQuarterlyReviewTaskUtils.isQuarterStart(today)) {
            AccountPlanQuarterlyReviewTaskService.generateQuarterlyReviewTasks();
        }
        
        AccountPlanQuarterlyReviewTaskService.monitorInactivityAndNotify();
    }
}