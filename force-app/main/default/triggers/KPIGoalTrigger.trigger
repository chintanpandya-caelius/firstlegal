trigger KPIGoalTrigger on KPI_Goal__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            KPIGoalTriggerHandler.handleBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            KPIGoalTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}