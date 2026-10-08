trigger AccountDataChangeLogger on Account_Data_Change__e (after insert) {
    List<Event_Log__c> logs = new List<Event_Log__c>();
    for (Account_Data_Change__e e : Trigger.new) {
        logs.add(new Event_Log__c(
            Changed_Object__c   = e.ChangedObject__c,
            Change_Type__c      = e.ChangeType__c,
            Change_Parent_Id__c = e.ChangeParentId__c,
            Change_Actual_Id__c = e.ChangeActualId__c,
            Change_Timestamp__c = e.ChangeTimestamp__c));
    }
    insert logs;
}