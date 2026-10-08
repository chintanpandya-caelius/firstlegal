trigger CaseTrigger on Case (after insert, after update) {

    // ─── AFTER INSERT ───
    if (Trigger.isAfter && Trigger.isInsert) {
        // NOVA-9004 Story 1: eDiscovery ticket created acknowledgment
        EDiscoveryNotificationHandler.handleAfterInsert(Trigger.new);
        TicketFspFcpNotificationService.process(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null, Trigger.isInsert, Trigger.isUpdate);
    }

    // ─── AFTER UPDATE ───
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Existing: WoC/Wo3P reminder lifecycle
        ReminderTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);

        // NOVA-9004: eDiscovery status-based notifications
        EDiscoveryNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);

         TicketFspFcpNotificationService.process(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null, Trigger.isInsert, Trigger.isUpdate);
    }
}