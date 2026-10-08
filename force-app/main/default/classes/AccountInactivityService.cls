/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Service class for high priority task creation batch, 
                    to get the latest configuration from metedata
* @Story Number : 5450
*/

public with sharing class AccountInactivityService {

    public static void processAccounts(List<Account> accounts, AccountAutomationConfig config) {
        if (accounts == null || accounts.isEmpty()) {return;}

        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            accountIds.add(acc.Id);
        }

        Map<Id, Datetime> latestActivityByAccount = getLatestActivityDates(accountIds);
        Set<Id> accountsWithOpenEscalation = getAccountsWithOpenEscalation(accountIds);

        List<Task> tasksToInsert = new List<Task>();
        DateTime inactivityThreshold = System.now().addMonths(-2);

        for (Account acc : accounts) {
            if (accountsWithOpenEscalation.contains(acc.Id)) {continue;}
            
            Datetime latestActivity = latestActivityByAccount.get(acc.Id);
            Boolean isInactive = false;
            if (latestActivity == null) { 
                isInactive = true;
            } 
            else if ( latestActivity <= inactivityThreshold) {
                isInactive = true;
            }
            if (!isInactive) {
                continue;
            }
            Task inactivityTask = buildInactivityTask(acc,latestActivity,config);
            tasksToInsert.add(inactivityTask);
        }

        if (!tasksToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(tasksToInsert,false);
        }
    }

    private static Map<Id, Datetime> getLatestActivityDates(Set<Id> accountIds) {

        Map<Id, Datetime> latestActivityByAccount = new Map<Id, Datetime>();
        for (AggregateResult ar : [SELECT WhatId accountId, MAX(CreatedDate) latestDate
                					FROM Task WHERE WhatId IN :accountIds
                					GROUP BY WhatId
                                 ]
        ) {
            Id accountId = (Id) ar.get('accountId');
            Datetime latestDate = (Datetime) ar.get('latestDate');
            latestActivityByAccount.put(accountId, latestDate);
        }

        for (AggregateResult ar : [
                SELECT WhatId accountId,MAX(CreatedDate) latestDate
                FROM Event
                WHERE WhatId IN :accountIds
                GROUP BY WhatId]) 
        {
            Id accountId = (Id) ar.get('accountId');
            Datetime eventDate = (Datetime) ar.get('latestDate');

            if (!latestActivityByAccount.containsKey(accountId)) {
                latestActivityByAccount.put(accountId, eventDate);
            } else {
                Datetime existingDate = latestActivityByAccount.get(accountId);
                if (eventDate > existingDate) {
                    latestActivityByAccount.put(accountId,eventDate);
                }
            }
        }
        return latestActivityByAccount;
    }

    private static Set<Id>
        getAccountsWithOpenEscalation(
            Set<Id> accountIds
        ) {
        Set<Id> result = new Set<Id>();
        for (Task task : [
				SELECT Id, WhatId, Status
                FROM Task
                WHERE WhatId IN :accountIds
                AND IsClosed = FALSE
		]) {
            result.add(task.WhatId);
        }
        return result;
    }

    private static Task buildInactivityTask(
        Account acc,
        Datetime latestActivity,
        AccountAutomationConfig config
    ) {

        Task task = new Task();
        task.OwnerId = acc.OwnerId;
        task.WhatId = acc.Id;
        task.Subject = 'High Priority – Account Inactive for More Than 2 Months';
        task.Priority = config.inactivityTaskPriority;
        task.Status = 'Not Started';
        task.ActivityDate = Date.today();
        task.Description = buildDescription(acc, latestActivity);

        return task;
    }
    
    private static String buildDescription(
        Account acc,
        Datetime latestActivity
    ) {
        List<String> details = new List<String>();
        details.add('Account Name: ' + acc.Name);
        details.add('Account Owner: ' + (acc.Owner != null ? acc.Owner.Name : 'N/A'));
        details.add('Last Task/Event Created: ' +(latestActivity != null? String.valueOf(latestActivity): 'No Task or Event found'));
        details.add('Account Status: ' +String.valueOf(acc.Status__c));
        details.add('Annual Revenue: ' + String.valueOf(acc.AnnualRevenue));

        return String.join(details, '\n');
    }
}