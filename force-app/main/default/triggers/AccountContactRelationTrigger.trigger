trigger AccountContactRelationTrigger on AccountContactRelation (after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            AccountContactRelationTriggerHandler.handle(Trigger.new, Trigger.oldMap, false);
        } else if (Trigger.isDelete) {
            AccountContactRelationTriggerHandler.handle(null, Trigger.oldMap, true);
        }
    }
}