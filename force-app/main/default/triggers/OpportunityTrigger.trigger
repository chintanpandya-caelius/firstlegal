trigger OpportunityTrigger on Opportunity (before insert, before update, after update,after insert) {
    
 	if (Trigger.isAfter) {
             if (Trigger.isInsert) {
         		OpportunityActivityHandler.resetStaleOpportunities(Trigger.new);
			}
    }
     
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            OpportunityTriggerHandler.beforeInsert(Trigger.new);
            //OpportunityStaleDealHandler.handleBeforeInsertUpdate(Trigger.new,null);
        }
        
        if (Trigger.isUpdate) {
            OpportunityTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
            //OpportunityStaleDealHandler.handleBeforeInsertUpdate(Trigger.new,Trigger.oldMap);
        }
    }

    if (Trigger.isAfter) {
        if (Trigger.isUpdate) {
            OpportunityTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}