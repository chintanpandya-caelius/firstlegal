public class AccountEngagementScheduler implements Schedulable {

    // Daily at 1:00 AM
    public static final String DAILY_CRON = '0 0 1 * * ?';

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new AccountEngagementBatch(), 200);
    }
}