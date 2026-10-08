public with sharing class OpportunityTriggerHelper {

    public static void handleBeforeInsert(List<Opportunity> newOpportunities){
        OpportunityDuplicateHandler.checkDuplicates(newOpportunities);
    }

    public static void handleBeforeUpdate(List<Opportunity> newOpportunities){
        OpportunityDuplicateHandler.checkDuplicates(newOpportunities);
    }
}