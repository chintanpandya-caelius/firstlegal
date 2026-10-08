/**
 * ReminderSchedulable
 * Runs every 30 minutes to process due reminders.
 * 
 * SCHEDULE THIS AFTER DEPLOYMENT:
 * Execute in Anonymous Apex:
 * 
 *   // Schedule to run every 30 minutes (two jobs needed)
 *   System.schedule('Reminder Processor :00', '0 0 * * * ?', new ReminderSchedulable());
 *   System.schedule('Reminder Processor :30', '0 30 * * * ?', new ReminderSchedulable());
 * 
 * TO UNSCHEDULE:
 *   for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Reminder Processor%']) {
 *       System.abortJob(ct.Id);
 *   }
 */
public class ReminderSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Process WoC reminders (main flow)
        ReminderService.processDueReminders();

        // Process Wo3P reminders (Court & Process, Client Care)
        ReminderService.processWo3pReminders();
    }
}