public class ABMMultiContactEngagementScheduler
    implements Schedulable {

    public void execute(SchedulableContext sc) {

        Database.executeBatch(
            new ABMMultiContactEngagementBatch(),
            200
        );
    }
}