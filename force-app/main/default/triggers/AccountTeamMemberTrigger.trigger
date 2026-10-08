trigger AccountTeamMemberTrigger on AccountTeamMember (after insert, after update, after delete, after undelete) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUndelete) {
            AccountTeamMemberTriggerHelper.handleRollup(Trigger.new);
        } else if (Trigger.isUpdate) {
            AccountTeamMemberTriggerHelper.handleUpdate(Trigger.new, Trigger.oldMap);
        } else if (Trigger.isDelete) {
            AccountTeamMemberTriggerHelper.handleRollup(Trigger.old);
        }
    }
}