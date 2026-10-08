trigger AccountTrigger on Account ( before insert, before update, after insert, after update) {
          
    if (Trigger.isBefore) {
        
        AccountHelper.handleBeforeSave(Trigger.new,Trigger.isInsert ? null : Trigger.oldMap);
    }
    
    if (Trigger.isBefore) {
        
        if (Trigger.isUpdate) {
            AccountTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AccountNotificationHandler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            AccountNotificationHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }

}