trigger AccountTeamApprovalTrigger on Account_Team_Approval__c (before insert, after insert, before update, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        AccountTeamApprovalHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        AccountTeamApprovalHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        AccountTeamApprovalHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        AccountTeamApprovalHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}