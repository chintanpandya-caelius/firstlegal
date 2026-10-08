trigger SharedNoteLinkTrigger on Shared_Note_Link__c (after insert) {
    SharedNoteLinkTriggerHandler.handleAfterSave(Trigger.new);
}