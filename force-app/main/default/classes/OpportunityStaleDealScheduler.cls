public with sharing class OpportunityStaleDealScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Calls the batch class with default batch size of 200
        OpportunityStaleDealBatch batch = new OpportunityStaleDealBatch();
        Database.executeBatch(batch, 200);
    }

    public static String scheduleDailyAt9AM() {
        String jobName = 'Daily Stale Opportunity Check - 9 AM';
        String cronExp = '0 0 9 * * ?'; // Runs every day at 9:00 AM
        return System.schedule(jobName, cronExp, new OpportunityStaleDealScheduler());
    }
}