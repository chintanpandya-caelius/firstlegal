public with sharing class OpportunityStaleDealBatch implements Database.Batchable<sObject>, Database.Stateful {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query open opportunities where Qualification Date is older than 60 days
        Date sixtyDaysAgo = Date.today().addDays(-60);
        
        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, CloseDate, Stage_Qualification_Date__c, 
                   Last_Activity_Date__c, IsStale__c, Stale_Date__c, 
                   ForecastCategoryName, Territory2Id
            FROM Opportunity
            WHERE IsClosed = FALSE
              AND Stage_Qualification_Date__c != NULL
              AND Stage_Qualification_Date__c <= :sixtyDaysAgo
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        Map<Id, Id> oppToManagerMap = new Map<Id, Id>();

        // Query Notification Type
        List<CustomNotificationType> notificationTypes = [
            SELECT Id FROM CustomNotificationType 
            WHERE DeveloperName = 'Stale_Opportunity_Alert' 
            LIMIT 1
        ];
        Id notificationTypeId = notificationTypes.isEmpty() ? null : notificationTypes[0].Id;

        // Collect Territory IDs to find assigned Territory Managers
        Set<Id> territoryIds = new Set<Id>();
        for (Opportunity opp : scope) {
            if (opp.Territory2Id != null) {
                territoryIds.add(opp.Territory2Id);
            }
        }

        // Map Territory Manager Users (Fixed: Used UserId instead of UserOrGroupId)
        Map<Id, Id> territoryToManagerMap = new Map<Id, Id>();
        if (!territoryIds.isEmpty()) {
            for (UserTerritory2Association uta : [
                SELECT UserId, Territory2Id 
                FROM UserTerritory2Association 
                WHERE Territory2Id IN :territoryIds 
                  AND RoleInTerritory2 IN ('Territory Manager', 'Manager')
            ]) {
                territoryToManagerMap.put(uta.Territory2Id, uta.UserId);
            }
        }

        Date today = Date.today();

        for (Opportunity opp : scope) {
            Date lastTouch = opp.Last_Activity_Date__c != null ? opp.Last_Activity_Date__c : opp.Stage_Qualification_Date__c;
            Integer daysInactive = lastTouch.daysBetween(today);

            // Double check 60 days inactivity criteria
            if (daysInactive >= 60) {
                Boolean isUpdated = false;

                // Update IsStale__c and Stale_Date__c
                if (!opp.IsStale__c) {
                    opp.IsStale__c = true;
                    opp.Stale_Date__c = today;
                    isUpdated = true;
                }

                // AC Forecast Impact: Exclude from Commit and Best Case rollups
                if (opp.ForecastCategoryName == 'Commit' || opp.ForecastCategoryName == 'BestCase') {
                    opp.ForecastCategoryName = 'Omitted';
                    isUpdated = true;
                }

                if (isUpdated) {
                    oppsToUpdate.add(opp);
                }

                // Resolve Territory Manager or fallback to Opp Owner
                Id recipientId = territoryToManagerMap.containsKey(opp.Territory2Id) 
                    ? territoryToManagerMap.get(opp.Territory2Id) 
                    : opp.OwnerId;

                if (recipientId != null && notificationTypeId != null) {
                    oppToManagerMap.put(opp.Id, recipientId);
                }
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;

            // Send Bell Notifications
            for (Opportunity opp : oppsToUpdate) {
                Id recipientId = oppToManagerMap.get(opp.Id);
                if (recipientId != null && notificationTypeId != null) {
                    sendBellNotification(notificationTypeId, opp, recipientId);
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('OpportunityStaleDealBatch completed successfully.');
    }

    private void sendBellNotification(Id notificationTypeId, Opportunity opp, Id recipientId) {
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle('Stale Opportunity Alert: ' + opp.Name);
        notification.setBody('This opportunity passed 60 days since qualification with no activity. It has been marked as stale.');
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTargetId(opp.Id);

        try {
            notification.send(new Set<String>{ recipientId });
        } catch (Exception e) {
            System.debug('Error sending custom notification: ' + e.getMessage());
        }
    }
}