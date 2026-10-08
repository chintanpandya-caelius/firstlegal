global with sharing class AnnualComplianceScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {
       Database.executeBatch(new AnnualComplianceBatch(),200);

    }

    public static void scheduleJob() {

        // Runs every year on December 1st at 2 AM

        String cronExp = '0 0 2 1 12 ?';

        System.schedule( 'Annual Compliance Job',cronExp,new AnnualComplianceScheduler());

    }

}