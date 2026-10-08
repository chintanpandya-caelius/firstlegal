public class ReminderTriggerHandler {

    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Case> enteredWoC = new List<Case>();
        List<Case> leftWoC = new List<Case>();
        List<Case> enteredWo3P = new List<Case>();
        List<Case> leftWo3P = new List<Case>();

        for (Case c : newCases) {
            Case oldCase = oldMap.get(c.Id);
            String newStatus = c.Status;
            String oldStatus = oldCase.Status;

            // Skip if status didn't change
            if (newStatus == oldStatus) continue;

            // ─── ENTERED Waiting on Customer ───
            if (newStatus == ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER &&
                oldStatus != ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER) {
                enteredWoC.add(c);
            }

            // ─── LEFT Waiting on Customer ───
            if (oldStatus == ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER &&
                newStatus != ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER) {
                leftWoC.add(c);
            }

            // ─── ENTERED Waiting on 3rd Party ───
            if (newStatus == ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY &&
                oldStatus != ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY) {
                enteredWo3P.add(c);
            }

            // ─── LEFT Waiting on 3rd Party ───
            if (oldStatus == ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY &&
                newStatus != ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY) {
                leftWo3P.add(c);
            }
        }

        // Process transitions
        if (!enteredWoC.isEmpty()) {
            ReminderService.initializeReminders(enteredWoC, oldMap);
        }
        if (!leftWoC.isEmpty()) {
            ReminderService.cancelReminders(leftWoC);
        }
        if (!enteredWo3P.isEmpty()) {
            initializeWo3pReminders(enteredWo3P, oldMap);
        }
        if (!leftWo3P.isEmpty()) {
            ReminderService.cancelReminders(leftWo3P);
        }
    }

    /**
     * Initialize Wo3P reminders (only for streams that support it).
     */
    private static void initializeWo3pReminders(List<Case> cases, Map<Id, Case> oldMap) {
        Set<Id> ownerIds = new Set<Id>();
        for (Case c : cases) ownerIds.add(c.OwnerId);

        Map<Id, Group> queueMap = new Map<Id, Group>(
            [SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']
        );
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN (SELECT RecordTypeId FROM Case WHERE Id IN :cases)]
        );

        List<Case> casesToUpdate = new List<Case>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : cases) {
            RecordType rt = rtMap.get(c.RecordTypeId);
            if (rt == null) continue;

            String queueDevName = null;
            Group q = queueMap.get(c.OwnerId);
            if (q != null) queueDevName = q.DeveloperName;

            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                rt.DeveloperName, queueDevName, c.SuppliedEmail
            );

            if (stream == null || !stream.hasWo3pReminder) continue;

            DateTime nextWo3p = DateTime.newInstance(
                BusinessDayCalculator.addBusinessDays(Date.today(), stream.wo3pIntervalDays),
                Time.newInstance(9, 0, 0, 0)
            );

            Case toUpdate = new Case(Id = c.Id);
            toUpdate.Reminder_Active__c = true;
            toUpdate.Next_Reminder_DateTime__c = nextWo3p;
            toUpdate.Reminder_Stream_Name__c = stream.streamName + ' (Wo3P)';
            casesToUpdate.add(toUpdate);

            FeedItem fi = new FeedItem();
            fi.ParentId = c.Id;
            fi.Body = '[Reminder Automation] Waiting on 3rd Party — reminder scheduled for: ' + nextWo3p.format('yyyy-MM-dd HH:mm');
            feedItems.add(fi);
        }

        if (!casesToUpdate.isEmpty()) update casesToUpdate;
        if (!feedItems.isEmpty()) insert feedItems;
    }
}