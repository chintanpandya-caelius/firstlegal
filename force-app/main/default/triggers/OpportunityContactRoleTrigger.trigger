trigger OpportunityContactRoleTrigger on OpportunityContactRole (
    before insert,
    before update,
    before delete
) {
    
    if (Trigger.isBefore && Trigger.isInsert) {
        OpportunityContactRoleHandler.validateDateRanges(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        OpportunityContactRoleHandler.validateDateRanges(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isDelete) {
        OpportunityContactRoleHandler.handleBeforeDelete(Trigger.old);
    }
}