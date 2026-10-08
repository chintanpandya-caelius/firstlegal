trigger LeadTrigger on Lead (before insert, before update, after insert, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        LeadTriggerHandler.beforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        LeadTriggerHandler.beforeUpdate(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        // LeadTriggerHandler.afterInsert already invokes LeadDuplicateHandler.process
        LeadTriggerHandler.afterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        // LeadTriggerHandler.afterUpdate already invokes LeadDuplicateHandler.process
        LeadTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}