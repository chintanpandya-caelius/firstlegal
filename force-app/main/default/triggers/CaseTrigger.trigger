trigger CaseTrigger on Case (before update, after insert, after update) {
    // ─── BEFORE UPDATE ───
    if (Trigger.isBefore && Trigger.isUpdate) {
        CaseTriggerHandler.captureCaseClosure(Trigger.new, Trigger.oldMap);
    }

    // ─── AFTER INSERT ───
    if (Trigger.isAfter && Trigger.isInsert) {
        // NOVA-9004 Story 1: eDiscovery ticket created acknowledgment
        EDiscoveryNotificationHandler.handleAfterInsert(Trigger.new);
    }

    // ─── AFTER UPDATE ───
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Existing: WoC/Wo3P reminder lifecycle
        ReminderTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);

        // NOVA-9004: eDiscovery status-based notifications
        EDiscoveryNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }

}