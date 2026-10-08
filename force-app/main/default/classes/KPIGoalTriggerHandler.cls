public with sharing class KPIGoalTriggerHandler {

    public static void handleBeforeInsert(List<KPI_Goal__c> newGoals) {
        validateUniqueActiveGoals(newGoals, null);
    }

    public static void handleBeforeUpdate(List<KPI_Goal__c> newGoals, Map<Id, KPI_Goal__c> oldMap) {
        validateUniqueActiveGoals(newGoals, oldMap);
    }

    private static void validateUniqueActiveGoals(List<KPI_Goal__c> newGoals, Map<Id, KPI_Goal__c> oldMap) {
        Set<Id> userIds = new Set<Id>();
        Set<String> periods = new Set<String>();

        for (KPI_Goal__c goal : newGoals) {
            Boolean isRelevant = goal.Active__c && goal.User__c != null;
            Boolean stateChanged = (oldMap == null) || 
                                   (goal.Active__c != oldMap.get(goal.Id).Active__c) || 
                                   (goal.Reporting_Period__c != oldMap.get(goal.Id).Reporting_Period__c) ||
                                   (goal.User__c != oldMap.get(goal.Id).User__c) ||
                                   (goal.Effective_From__c != oldMap.get(goal.Id).Effective_From__c) ||
                                   (goal.Effective_To__c != oldMap.get(goal.Id).Effective_To__c);

            if (isRelevant && stateChanged) {
                userIds.add(goal.User__c);
                periods.add(goal.Reporting_Period__c);
            }
        }

        if (userIds.isEmpty()) {
            return;
        }

        // Query active goals for the same users and reporting periods
        List<KPI_Goal__c> existingGoals = [
            SELECT Id, User__c, Reporting_Period__c, Effective_From__c, Effective_To__c 
            FROM KPI_Goal__c 
            WHERE Active__c = true 
              AND User__c IN :userIds 
              AND Reporting_Period__c IN :periods
              AND Id NOT IN :newGoals
            WITH USER_MODE
        ];

        for (KPI_Goal__c newGoal : newGoals) {
            if (!newGoal.Active__c || newGoal.User__c == null) {
                continue;
            }

            Date newStart = newGoal.Effective_From__c != null ? newGoal.Effective_From__c : Date.newInstance(1900, 1, 1);
            Date newEnd = newGoal.Effective_To__c != null ? newGoal.Effective_To__c : Date.newInstance(4000, 12, 31);

            // Check against existing database records
            for (KPI_Goal__c existing : existingGoals) {
                if (newGoal.User__c == existing.User__c && newGoal.Reporting_Period__c == existing.Reporting_Period__c) {
                    Date existingStart = existing.Effective_From__c != null ? existing.Effective_From__c : Date.newInstance(1900, 1, 1);
                    Date existingEnd = existing.Effective_To__c != null ? existing.Effective_To__c : Date.newInstance(4000, 12, 31);

                    // Overlap Condition: (StartA <= EndB) AND (EndA >= StartB)
                    if (newStart <= existingEnd && newEnd >= existingStart) {
                        newGoal.addError('An active KPI Goal already exists for this User, Reporting Period, and date range. Please deactivate or adjust the date range of the conflicting goal.');
                        break;
                    }
                }
            }
        }
    }
}