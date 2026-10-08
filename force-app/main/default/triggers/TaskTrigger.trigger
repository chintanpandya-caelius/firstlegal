trigger TaskTrigger on Task (before insert, before update, before delete, after insert) {

    if (Trigger.isBefore) {
       TaskTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.isDelete);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        FollowUpTaskHandler.createFollowUpTasks(Trigger.new);
        OpportunityActivityHandler.resetStaleOpportunities(Trigger.new);
    }
}