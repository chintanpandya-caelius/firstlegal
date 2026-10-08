trigger OpportunityContactRoleTrigger on OpportunityContactRole (before insert, before update, before delete) {

    if (Trigger.isBefore) {
        
        // Handle Insert and Update events to validate non-overlapping date ranges
        if (Trigger.isInsert || Trigger.isUpdate) {
            OpportunityContactRoleHandler.validateDateRanges(Trigger.new);
        }

        // Handle Delete events to restrict non-admin deletion
        if (Trigger.isDelete) {
            OpportunityContactRoleHandler.handleBeforeDelete(Trigger.old);
        }
    }
}