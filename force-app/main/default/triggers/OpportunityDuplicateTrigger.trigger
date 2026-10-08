trigger OpportunityDuplicateTrigger on Opportunity (before insert, before update) {

    if(Trigger.isBefore){

        if(Trigger.isInsert){
            OpportunityTriggerHelper.handleBeforeInsert(Trigger.new);
        }
        else if(Trigger.isUpdate){
            OpportunityTriggerHelper.handleBeforeUpdate(Trigger.new);
        }
    }
}