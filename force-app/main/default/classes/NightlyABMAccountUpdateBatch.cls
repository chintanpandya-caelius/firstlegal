public class NightlyABMAccountUpdateBatch implements Database.Batchable<SObject>, Schedulable, Database.Stateful {

    private List<Task> tasksToInsert = new List<Task>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, OwnerId, LastModifiedDate,
                   Engagement_Score__c,
                   Revenue_Potential_Score__c,
                   ABM_Target_Status__c,
                   Account_Performance_Indicator__c,
                   Opportunity_Activity_Indicator__c,
                   Influence_Mapping_Gap__c,
                   Influence_Mapping_Status__c,
                   High_Influence_Contact_Count__c,
                   Champion_Coach_Contact_Count__c,
                   Medium_Influence_Contact_Count__c,
                   Low_No_Influence_Contact_Count__c,
                   Unknown_Influence_Contact_Count__c,
                   (SELECT Id, Contact_Influence_Role__c FROM AccountContactRelations),
                   (SELECT Id, StageName, IsClosed, LastModifiedDate FROM Opportunities)
            FROM Account
            WHERE ABM_Target_Account__c = true
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        List<Account> accountsToUpdate = new List<Account>();

        for (Account acc : scope) {

            Integer countHighInfluence   = 0;
            Integer countChampionCoach   = 0;
            Integer countMediumInfluence = 0;
            Integer countLowNoInfluence  = 0;
            Integer countUnknownInfluence = 0;

            for (AccountContactRelation acr : acc.AccountContactRelations) {
                String role = acr.Contact_Influence_Role__c;
                if (role == 'High Influence') {
                    countHighInfluence++;
                } else if (role == 'Champion/Coach') {
                    countChampionCoach++;
                } else if (role == 'Medium Influence') {
                    countMediumInfluence++;
                } else if (role == 'Low Influence' || role == 'No Influence') {
                    countLowNoInfluence++;
                } else {
                    countUnknownInfluence++;
                }
            }

            Boolean influenceMappingGap = (countHighInfluence + countChampionCoach) == 0;

            acc.High_Influence_Contact_Count__c    = countHighInfluence;
            acc.Champion_Coach_Contact_Count__c    = countChampionCoach;
            acc.Medium_Influence_Contact_Count__c  = countMediumInfluence;
            acc.Low_No_Influence_Contact_Count__c  = countLowNoInfluence;
            acc.Unknown_Influence_Contact_Count__c = countUnknownInfluence;
            acc.Influence_Mapping_Gap__c           = influenceMappingGap;

            String currentStatus = acc.Influence_Mapping_Status__c;
            if (String.isBlank(currentStatus) || currentStatus == 'Not Started') {
                acc.Influence_Mapping_Status__c = influenceMappingGap ? 'Gap Identified' : 'In Progress';
            }
            
            if (acc.ABM_Target_Status__c == 'Active') {

                String previousIndicator = acc.Account_Performance_Indicator__c;

                Boolean hasActiveOpp = false;
                Boolean hasRecentMovement = false;
                Date thirtyDaysAgo = Date.today().addDays(-30);

                for (Opportunity opp : acc.Opportunities) {
                    if (opp.IsClosed == false) {
                        hasActiveOpp = true;
                    }
                    if (opp.LastModifiedDate != null && opp.LastModifiedDate.date() >= thirtyDaysAgo) {
                        hasRecentMovement = true;
                    }
                }

                String opportunityActivityIndicator;
                Integer opportunityActivityPoints;
                if (hasActiveOpp) {
                    opportunityActivityIndicator = 'Active Opportunity';
                    opportunityActivityPoints = 25;
                } else if (hasRecentMovement) {
                    opportunityActivityIndicator = 'Recent Movement';
                    opportunityActivityPoints = 15;
                } else {
                    opportunityActivityIndicator = 'No Activity';
                    opportunityActivityPoints = 0;
                }
                acc.Opportunity_Activity_Indicator__c = opportunityActivityIndicator;

                Integer engagementPoints = engagementPoints(acc.Engagement_Score__c);
                Integer revenuePoints    = revenuePoints(acc.Revenue_Potential_Score__c);
                Integer lastInteractionPoints = lastInteractionPoints(acc);

                Integer totalScore = engagementPoints + revenuePoints
                                     + opportunityActivityPoints + lastInteractionPoints;

                String indicator;
                if (totalScore >= 70) {
                    indicator = 'Hot';
                } else if (totalScore >= 35) {
                    indicator = 'Warm';
                } else {
                    indicator = 'Cold';
                }
                acc.Account_Performance_Indicator__c = indicator;

               
                if (indicator == 'Cold' && previousIndicator != 'Cold') {
                    tasksToInsert.add(new Task(
                        WhatId       = acc.Id,
                        OwnerId      = acc.OwnerId,
                        Subject      = 'Review Underperforming ABM Account',
                        Description  = 'This ABM target account has been flagged as Cold',
                        Priority     = 'High',
                        Status       = 'New',
                        ActivityDate = Date.today().addDays(3)
                    ));
                }
            }

            accountsToUpdate.add(acc);
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }
    }

    private Integer engagementPoints(Decimal engagementScore) {
        if (engagementScore == null) { return 0; }
        if (engagementScore >= 70) { return 30; }
        if (engagementScore >= 35) { return 15; }
        return 0;
    }

    private Integer revenuePoints(Decimal revenuePotentialScore) {
        if (revenuePotentialScore == null) { return 0; }
        if (revenuePotentialScore >= 70) { return 30; }
        if (revenuePotentialScore >= 35) { return 15; }
        return 0;
    }

    
    private Integer lastInteractionPoints(Account acc) {
        Datetime lastModified = acc.LastModifiedDate;
        if (lastModified == null) { return 0; }
        Integer daysSince = lastModified.date().daysBetween(Date.today());
        if (daysSince <= 30) { return 15; }
        if (daysSince <= 90) { return 8; }
        return 0;
    }

    
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new NightlyABMAccountUpdateBatch(), 200);
    }
}