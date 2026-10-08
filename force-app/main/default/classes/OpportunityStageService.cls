public without sharing class OpportunityStageService {

    // Stage names
    public static final String STAGE_NURTURE       = 'Nurture';
    public static final String STAGE_QUALIFICATION = 'Qualification';
    public static final String STAGE_DISCOVERY     = 'Discovery';
    public static final String STAGE_PROPOSAL      = 'Proposal';
    public static final String STAGE_NEGOTIATION   = 'Negotiation';
    public static final String STAGE_CLOSED_WON    = 'Closed Won';
    public static final String STAGE_CLOSED_LOST   = 'Closed Lost';

    // Order types
    public static final String ORDER_TYPE_COD      = 'COD';
    public static final String ORDER_TYPE_OPPOSING = 'Opposing Council';
    public static final String ORDER_TYPE_TERMS    = 'Terms';

    // SLA
    public static final String SLA_S1 = 'S1';
    public static final String SLA_S2 = 'S2';

    // Revenue Types that force Matter/Case Number to be required at Qualification exit
    private static final Set<String> MATTER_NUMBER_REQUIRED_REVENUE_TYPES = new Set<String>{
        'Class Action', 'Matter Specific Project', 'Worker\'s Comp'
    };


    private static Integer recursionCount = 0;
    private static final Integer MAX_RECURSION = 5;



    // Before Insert Functions
    // Sets the default SLA Tier on creation: S1 (locked) for COD/Opposing Council, S2 for Terms
    public static void applyCreateDefaults(List<Opportunity> newOpps) {
        for (Opportunity opp : newOpps) {
            if (opp.Order_Type__c == ORDER_TYPE_COD || opp.Order_Type__c == ORDER_TYPE_OPPOSING) {
                opp.SLA_Tier__c = SLA_S1;
            } else if (opp.Order_Type__c == ORDER_TYPE_TERMS && String.isBlank(opp.SLA_Tier__c)) {
                opp.SLA_Tier__c = SLA_S2;
            }
        }
    }



    // Before Update Functions
    public static void enforceSlaLock(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            Boolean lockedOrderType = (opp.Order_Type__c == ORDER_TYPE_COD || opp.Order_Type__c == ORDER_TYPE_OPPOSING);

            Boolean orderTypeChangedToLocked = lockedOrderType && opp.Order_Type__c != oldOpp.Order_Type__c;
            if (opp.StageName == STAGE_NURTURE && orderTypeChangedToLocked) {
                opp.SLA_Tier__c = SLA_S1;
                continue;
            }

            if (lockedOrderType && opp.SLA_Tier__c != oldOpp.SLA_Tier__c) {
                opp.SLA_Tier__c.addError('SLA is fixed to S1 for COD / Opposing Council orders and cannot be changed.');
            }
        }
    }
    
    public static void captureProbabilityHistory(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.Probability != oldOpp.Probability) {
                opp.Previous_Probability__c = oldOpp.Probability;
            }
        }
    }

    // Stamps the date/time Qualification was first entered. Only ever set once
    public static void stampQualificationEnteredDate(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            Boolean enteringQualification = oldOpp.StageName != STAGE_QUALIFICATION && opp.StageName == STAGE_QUALIFICATION;
            if (enteringQualification && opp.Qualification_Entered_Date__c == null) {
                opp.Qualification_Entered_Date__c = System.now();
            }
        }
    }

    public static void validateManualTransitions(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        Set<Id> accountIds = new Set<Id>();
        Set<Id> oppIdsNeedingRelatedData = new Set<Id>();

        for (Opportunity opp : newOpps) {
            if (opp.AccountId != null) accountIds.add(opp.AccountId);

            Opportunity oldOpp = oldMap.get(opp.Id);
            if (oldOpp.StageName != opp.StageName) {
                oppIdsNeedingRelatedData.add(opp.Id);
            }
        }

        Map<Id, Account> accountsById = accountIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([SELECT Id, Status__c,Terms__c FROM Account WHERE Id IN :accountIds]);

        Set<Id> oppIdsWithProducts = new Set<Id>();
        Map<Id, List<Task>> oppTasks = new Map<Id, List<Task>>();
        if (!oppIdsNeedingRelatedData.isEmpty()) {
            for (Quote q : [
                SELECT OpportunityId FROM Quote WHERE OpportunityId IN :oppIdsNeedingRelatedData AND LineItemCount > 0
            ]) {
                oppIdsWithProducts.add(q.OpportunityId);
            }
            for (Task t : [
                SELECT WhatId, CompletedDateTime FROM Task
                WHERE WhatId IN :oppIdsNeedingRelatedData AND Status = 'Completed'
            ]) {
                if (!oppTasks.containsKey(t.WhatId)) oppTasks.put(t.WhatId, new List<Task>());
                oppTasks.get(t.WhatId).add(t);
            }
        }

        // Opportunity Contact Role count per Opportunity 
        Map<Id, Integer> ocrCountByOpp = new Map<Id, Integer>();
        if (!oppIdsNeedingRelatedData.isEmpty()) {
            for (AggregateResult ar : [
                SELECT OpportunityId oid, COUNT(Id) cnt FROM OpportunityContactRole
                WHERE OpportunityId IN :oppIdsNeedingRelatedData GROUP BY OpportunityId
            ]) {
                ocrCountByOpp.put((Id) ar.get('oid'), (Integer) ar.get('cnt'));
            }
        }
        
        Set<Id> oppIdsWithQualifyingNote = new Set<Id>();
        if (!oppIdsNeedingRelatedData.isEmpty()) {
            for (Shared_Note_Link__c link : [
                SELECT Opportunity__c
                FROM Shared_Note_Link__c
                WHERE Opportunity__c IN :oppIdsNeedingRelatedData
                AND Shared_Note__r.Note_Type__c IN ('Pain Point', 'Technical')
            ]) {
                oppIdsWithQualifyingNote.add(link.Opportunity__c);
            }
        }

        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (oldOpp.StageName == opp.StageName) continue;

            Account acct = opp.AccountId != null ? accountsById.get(opp.AccountId) : null;

            // ---- Block manual/Path entry into Qualification unless Nurture's exit criteria are met ----
            if (opp.StageName == STAGE_QUALIFICATION && oldOpp.StageName == STAGE_NURTURE) {
                Boolean hasProducts = oppIdsWithProducts.contains(opp.Id);
                Boolean hasContactRole = ocrCountByOpp.containsKey(opp.Id) && ocrCountByOpp.get(opp.Id) > 0;
                Boolean hasCompletedActivity = oppTasks.containsKey(opp.Id) && !oppTasks.get(opp.Id).isEmpty();

                List<String> missing = getNurtureMissingRequirements(opp, hasProducts, hasContactRole, hasCompletedActivity);
                if (!missing.isEmpty()) {
                    opp.StageName.addError('Cannot move to Qualification - missing: ' + String.join(missing, '; '));
                }
            }

            // ---- Block manual/Path entry into Discovery unless Qualification's exit criteria are met ----
            if (opp.StageName == STAGE_DISCOVERY && oldOpp.StageName == STAGE_QUALIFICATION) {
                List<Task> completedTasks = oppTasks.containsKey(opp.Id) ? oppTasks.get(opp.Id) : new List<Task>();
                List<String> missing = getQualificationMissingRequirements(opp, completedTasks);
                if (!missing.isEmpty()) {
                    opp.StageName.addError('Cannot move to Discovery - missing: ' + String.join(missing, '; '));
                }
            }

            // ---- Block manual/Path entry into Proposal unless Discovery's exit criteria are met ----
            if (opp.StageName == STAGE_PROPOSAL && oldOpp.StageName == STAGE_DISCOVERY) {
				Boolean hasQualifyingNote = oppIdsWithQualifyingNote.contains(opp.Id);
                List<String> missing = getDiscoveryMissingRequirements(opp,hasQualifyingNote);
                if (!missing.isEmpty()) {
                    opp.StageName.addError('Cannot move to Proposal - missing: ' + String.join(missing, '; '));
                }
            }

            // ---- Proposal -> Negotiation: RFP always required, Account Status/T&C differ by Order Type ----
            if (oldOpp.StageName == STAGE_PROPOSAL && opp.StageName == STAGE_NEGOTIATION) {
                List<String> missing = new List<String>();
                if (opp.RFP__c != true) missing.add('RFP');
                if (opp.Order_Type__c == ORDER_TYPE_TERMS) {
                    if (acct == null || acct.Status__c != 'Active') missing.add('Account Status must be Active');
                    if (acct == null || acct.Terms__c != true) missing.add('Terms must be true for the linked Account');
                } else {
                    if (acct == null || acct.Status__c != 'Prospect') missing.add('Account Status must be Prospect');
                }
                if (!missing.isEmpty()) {
                    opp.StageName.addError('Cannot move to Negotiation - missing: ' + String.join(missing, '; '));
                }
            }

            // ---- Negotiation -> Closed Won: E-Discovery requires the approved checkbox ----
            if (oldOpp.StageName == STAGE_NEGOTIATION && opp.StageName == STAGE_CLOSED_WON
                && opp.Service_Line__c == 'E-Discovery') {
                if (opp.E_Discovery_Approved__c != true) {
                    opp.StageName.addError('Cannot close as Won - missing: E-Discovery Approved checkbox');
                }
            }

            // ---- E-Discovery cannot skip Negotiation and jump straight from Proposal to Closed Won ----
            if (oldOpp.StageName == STAGE_PROPOSAL && opp.StageName == STAGE_CLOSED_WON
                && opp.Service_Line__c == 'E-Discovery') {
                opp.StageName.addError('E-Discovery Opportunities must go through Negotiation before closing as Won.');
            }


        }
    }


    // After Update Functions

    public static void evaluateAutoAdvance(Set<Id> oppIds) {
        if (oppIds == null || oppIds.isEmpty() || recursionCount >= MAX_RECURSION) return;

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, StageName, Order_Type__c, Revenue_Type__c, Pre_Call_Document__c,
                   Estimated_Close_Date__c, Service_Line__c, Budget_Confirmed__c,
                   Estimated_Annual_Revenue__c, Estimated_Monthly_Revenue__c,
                   Estimated_Start_Date__c, Estimated_End_Date__c, Matter_Case_Number__c,
                   Qualification_Entered_Date__c, Lead_Source__c,
                   Estimated_Confirmed__c,Demo__c,
                   (SELECT Id FROM OpportunityContactRoles LIMIT 1)
            FROM Opportunity
            WHERE Id IN :oppIds
            AND StageName IN (:STAGE_NURTURE, :STAGE_QUALIFICATION, :STAGE_DISCOVERY)
        ]);
        if (opps.isEmpty()) return;

        // Opportunities with at least one Quote that has Products on it
        Set<Id> oppIdsWithProducts = new Set<Id>();
        for (Quote q : [SELECT OpportunityId FROM Quote WHERE OpportunityId IN :opps.keySet() AND LineItemCount > 0]) {
            oppIdsWithProducts.add(q.OpportunityId);
        }

        // Completed activities per Opportunity, with completion timestamp for the "second Activity must occur after entering Qualification" check
        Map<Id, List<Task>> oppTasks = new Map<Id, List<Task>>();
        for (Task t : [SELECT WhatId, CompletedDateTime FROM Task WHERE WhatId IN :opps.keySet() AND Status = 'Completed']) {
            if (!oppTasks.containsKey(t.WhatId)) oppTasks.put(t.WhatId, new List<Task>());
            oppTasks.get(t.WhatId).add(t);
        }
        
        Set<Id> oppIdsWithQualifyingNote = new Set<Id>();
        for (Shared_Note_Link__c link : [
            SELECT Opportunity__c
            FROM Shared_Note_Link__c
            WHERE Opportunity__c IN :opps.keySet()
            AND Shared_Note__r.Note_Type__c IN ('Pain Point', 'Technical')
        ]) {
            oppIdsWithQualifyingNote.add(link.Opportunity__c);
        }

        List<Opportunity> toUpdate = new List<Opportunity>();

        for (Opportunity opp : opps.values()) {
            Boolean hasProducts = oppIdsWithProducts.contains(opp.Id);
            Boolean hasContactRole = !opp.OpportunityContactRoles.isEmpty();
            List<Task> completedTasks = oppTasks.containsKey(opp.Id) ? oppTasks.get(opp.Id) : new List<Task>();
            Boolean hasCompletedActivity = !completedTasks.isEmpty();

            if (opp.StageName == STAGE_NURTURE) {
                if (getNurtureMissingRequirements(opp, hasProducts, hasContactRole, hasCompletedActivity).isEmpty()) {
                    toUpdate.add(new Opportunity(Id = opp.Id, StageName = STAGE_QUALIFICATION));
                }
            } else if (opp.StageName == STAGE_QUALIFICATION) {
                if (getQualificationMissingRequirements(opp, completedTasks).isEmpty()) {
                    toUpdate.add(new Opportunity(Id = opp.Id, StageName = STAGE_DISCOVERY));
                }
            } else if (opp.StageName == STAGE_DISCOVERY) {
                Boolean hasQualifyingNote = oppIdsWithQualifyingNote.contains(opp.Id);
                if (getDiscoveryMissingRequirements(opp, hasQualifyingNote).isEmpty()) {
                    toUpdate.add(new Opportunity(Id = opp.Id, StageName = STAGE_PROPOSAL));
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            recursionCount++;
            update toUpdate;
        }
    }


    // Closed Won Automations

    public static void createOnboardingTasks(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == STAGE_CLOSED_WON && oldOpp.StageName != STAGE_CLOSED_WON && opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        if (accountIds.isEmpty()) return;

        Map<Id, Account> accountsById = new Map<Id, Account>([SELECT Id, OwnerId FROM Account WHERE Id IN :accountIds]);

        List<Task> tasksToInsert = new List<Task>();
        for (Opportunity opp : newOpps) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == STAGE_CLOSED_WON && oldOpp.StageName != STAGE_CLOSED_WON) {
                Account acct = opp.AccountId != null ? accountsById.get(opp.AccountId) : null;
                if (acct == null) continue; 

                tasksToInsert.add(new Task(
                    WhatId       = opp.Id,
                    OwnerId      = acct.OwnerId,
                    Subject      = 'Onboarding Follow-up: ' + opp.Name,
                    ActivityDate = Date.today().addDays(7),
                    Status       = 'Not Started',
                    Priority     = 'Normal'
                ));
            }
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }


    // Private Helper Methods


    private static List<String> getNurtureMissingRequirements(Opportunity opp, Boolean hasProducts,Boolean hasContactRole, Boolean hasCompletedActivity) {
        List<String> missing = new List<String>();

        if (opp.Revenue_Type__c == 'Portfolio Growth') {
            return missing; 
        }

        if (String.isBlank(opp.Order_Type__c)) missing.add('Order Type');
        if (!hasProducts) missing.add('At least one Product on a Quote');
        if (!hasContactRole) missing.add('At least one Opportunity Contact Role');
        if (!hasCompletedActivity) missing.add('At least one completed Activity');

        if (opp.Order_Type__c == ORDER_TYPE_TERMS) {
            if (opp.Pre_Call_Document__c != true) missing.add('Pre-Call Document verified');
        }

        return missing;
    }

    private static List<String> getQualificationMissingRequirements(Opportunity opp, List<Task> completedTasks) {
        List<String> missing = new List<String>();

        if (opp.Estimated_Close_Date__c == null) missing.add('Estimated Close Date');
        if (String.isBlank(opp.Revenue_Type__c)) missing.add('Revenue Type');
        if (String.isBlank(opp.Service_Line__c)) missing.add('Service Line');

        Boolean matterRequired = MATTER_NUMBER_REQUIRED_REVENUE_TYPES.contains(opp.Revenue_Type__c);
        if (matterRequired && String.isBlank(opp.Matter_Case_Number__c)) missing.add('Matter/Case Number');

        Boolean secondActivityOk = false;
        if (opp.Qualification_Entered_Date__c != null && completedTasks.size() >= 2) {
            Integer afterEntry = 0;
            for (Task t : completedTasks) {
                if (t.CompletedDateTime != null && t.CompletedDateTime > opp.Qualification_Entered_Date__c) {
                    afterEntry++;
                }
            }
            secondActivityOk = afterEntry >= 1;
        }
        if (!secondActivityOk) missing.add('A second completed Activity occurring after Qualification was entered');

        if (opp.Order_Type__c == ORDER_TYPE_TERMS) {
            if (opp.Budget_Confirmed__c != true) missing.add('Budget Confirmed');
            if (opp.Estimated_Annual_Revenue__c == null) missing.add('Estimated Annual Revenue');
            if (opp.Estimated_Monthly_Revenue__c == null) missing.add('Estimated Monthly Revenue');
            if (opp.Estimated_Start_Date__c == null) missing.add('Estimated Start Date');
            if (opp.Estimated_End_Date__c == null) missing.add('Estimated End Date');
        }

        return missing;
    }

    // Discovery exit: Lead Source required; Terms adds Estimated Confirmed
    private static List<String> getDiscoveryMissingRequirements(Opportunity opp,Boolean hasQualifyingNote) {
        List<String> missing = new List<String>();

        if (String.isBlank(opp.Lead_Source__c)) missing.add('Lead Source');

        if (opp.Order_Type__c == ORDER_TYPE_TERMS) {
            if (opp.Estimated_Confirmed__c != true) missing.add('Estimated Confirmed');
            if (opp.Demo__c != true) missing.add('Demo');
			if (!hasQualifyingNote) missing.add('A Note of type Pain Point or Technical');

        }

        return missing;
    }
}