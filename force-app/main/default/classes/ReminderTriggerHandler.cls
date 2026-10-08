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

            if (newStatus == oldStatus) continue;

            if (newStatus == ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER &&
                oldStatus != ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER) {
                enteredWoC.add(c);
            }

            if (oldStatus == ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER &&
                newStatus != ReminderStreamConfig.STAGE_WAITING_ON_CUSTOMER) {
                leftWoC.add(c);
            }

            if (newStatus == ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY &&
                oldStatus != ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY) {
                enteredWo3P.add(c);
            }

            if (oldStatus == ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY &&
                newStatus != ReminderStreamConfig.STAGE_WAITING_ON_3RD_PARTY) {
                leftWo3P.add(c);
            }
        }

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
        Set<Id> rtIds = new Set<Id>();
        for (Case c : cases) {
            ownerIds.add(c.OwnerId);
            rtIds.add(c.RecordTypeId);
        }

        Map<Id, Group> queueMap = new Map<Id, Group>(
            [SELECT Id, DeveloperName FROM Group WHERE Id IN :ownerIds AND Type = 'Queue']
        );
        Map<Id, RecordType> rtMap = new Map<Id, RecordType>(
            [SELECT Id, DeveloperName FROM RecordType WHERE Id IN :rtIds]
        );

        List<Case> casesToUpdate = new List<Case>();
        List<FeedItem> feedItems = new List<FeedItem>();

        for (Case c : cases) {
            RecordType rt = rtMap.get(c.RecordTypeId);
            if (rt == null) continue;

            String queueDevName = (queueMap.containsKey(c.OwnerId)) ? queueMap.get(c.OwnerId).DeveloperName : null;

            ReminderStreamConfig.StreamDef stream = ReminderStreamConfig.findStream(
                rt.DeveloperName, queueDevName, c.SuppliedEmail
            );

            if (stream == null || !stream.hasWo3pReminder) continue;

            // FIX: Pass stream.businessHoursName to addBusinessDays to ensure correct BH are used
            // This resolves the "Method does not exist" error by matching the new 3-parameter signature
            DateTime nextWo3p = DateTime.newInstance(
                BusinessDayCalculator.addBusinessDays(Date.today(), stream.wo3pIntervalDays, stream.businessHoursName),
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