public without sharing class OpportunityTriggerHandler {

    public static void beforeInsert(List<Opportunity> newOpps) {
        // Existing naming convention
        OpportunityHandler.OpportunityNameGenerator(newOpps);

        // Stage 1 Nurture creation defaults
        OpportunityStageService.applyCreateDefaults(newOpps);
        
        // Revenue Validation Rules (NOVA-9787)
        OpportunityRevenueValidationHandler.handleBeforeSave(newOpps, null);
        
        // Territory Planning heat map (NOVA - 5961)
		OpportunityCurrentFYService.stampCurrentFY(newOpps);
    }

    public static void beforeUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        // Existing naming convention 
        OpportunityHandler.OpportunityNameGenerator(newOpps);

        // New: stage rules
		OpportunityStageService.captureProbabilityHistory(newOpps, oldMap);
        OpportunityStageService.enforceSlaLock(newOpps, oldMap);
        OpportunityStageService.validateManualTransitions(newOpps, oldMap);
        
        // Qualification Date
        OpportunityStageService.stampQualificationEnteredDate(newOpps, oldMap);

        // Revenue Validation Rules (NOVA-9787)
        OpportunityRevenueValidationHandler.handleBeforeSave(newOpps, oldMap);
        
        // Current FY stamping (Territory Planning heat map)
        OpportunityCurrentFYService.stampCurrentFY(newOpps);
    }

    public static void afterUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        Set<Id> idsToEvaluate = new Set<Id>();
        for (Opportunity o : newOpps) {
            idsToEvaluate.add(o.Id);
        }
        OpportunityStageService.evaluateAutoAdvance(idsToEvaluate);
        OpportunityStageService.createOnboardingTasks(newOpps, oldMap);
    }
}