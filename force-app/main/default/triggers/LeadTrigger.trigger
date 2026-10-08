trigger LeadTrigger on Lead (before insert, after insert, after update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        LeadTriggerHandler.beforeInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        
        LeadTriggerHandler.afterInsert(Trigger.new);
        
        LeadDuplicateHandler.process(Trigger.new, null); 
    }

    if (Trigger.isAfter && Trigger.isUpdate) {

        if(!LeadDuplicateHandler.isRunning) {
            LeadDuplicateHandler.process(Trigger.new, Trigger.oldMap);
        }

        LeadTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }

}