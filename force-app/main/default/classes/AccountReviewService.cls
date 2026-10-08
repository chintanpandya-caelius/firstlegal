/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Service class for generating recurring quarterly review Tasks for Account Owners and 
                    their direct managers to support account strategy alignment and performance reviews
* @Story Number : 5450
*/

public with sharing class AccountReviewService {
    
     public class QuarterInfo {
        public String quarterKey;
        public Date quarterStart;
        public Date quarterEnd;
    }

    public static void createQuarterlyTasks(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        
        QuarterInfo quarterInfo = getCurrentQuarter(Date.today());

        if (quarterInfo == null) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Id> assigneeIds = new Set<Id>();
        Set<String> automationKeys = new Set<String>();

        for (Account acc : accounts) {

            accountIds.add(acc.Id);
            if (acc.OwnerId != null) {
                assigneeIds.add(acc.OwnerId);
                automationKeys.add(buildAutomationKey(acc.Id, quarterInfo.quarterKey, acc.OwnerId));
            }
            if (acc.Owner != null && acc.Owner.ManagerId != null) {
                assigneeIds.add(acc.Owner.ManagerId);
                automationKeys.add( buildAutomationKey(acc.Id, quarterInfo.quarterKey, acc.Owner.ManagerId)); 
            }
        }

        Set<String> existingAutomationKeys = getExistingAutomationKeys(automationKeys);

        List<Task> tasksToInsert = new List<Task>();

        for (Account acc : accounts) {
            if (acc.OwnerId != null) {
                String ownerKey = buildAutomationKey(acc.Id, quarterInfo.quarterKey, acc.OwnerId);

                if (!existingAutomationKeys.contains(ownerKey)) {
                    tasksToInsert.add(buildQuarterlyTask(acc, acc.OwnerId, quarterInfo, ownerKey));
                    existingAutomationKeys.add(ownerKey);
                }
            }

            if (acc.Owner != null && acc.Owner.ManagerId != null) {
                String managerKey = buildAutomationKey(acc.Id, quarterInfo.quarterKey, acc.Owner.ManagerId);
                if (!existingAutomationKeys.contains(managerKey)) {
                    tasksToInsert.add(buildQuarterlyTask(acc, acc.Owner.ManagerId, quarterInfo,managerKey));
                    existingAutomationKeys.add(managerKey);
                }
            }
        }

        if (!tasksToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(tasksToInsert, false);
        }
    }
    
    private static QuarterInfo getCurrentQuarter(Date inputDate) {

        if (inputDate == null) {return null;}

        QuarterInfo result = new QuarterInfo();
        Integer month = inputDate.month();
        Integer quarterNumber = ((month - 1) / 3) + 1;
        Integer startMonth = ((quarterNumber - 1) * 3) + 1;
        Integer year = inputDate.year();
        Date quarterStart = Date.newInstance(year, startMonth, 1);
        Date quarterEnd = quarterStart.addMonths(3).addDays(-1);
        result.quarterStart = quarterStart;
        result.quarterEnd = quarterEnd;
        result.quarterKey = 'FY' + String.valueOf(year) + '-Q' + String.valueOf(quarterNumber);

        return result;
    }

    private static String buildAutomationKey(
        Id accountId,
        String quarterKey,
        Id assigneeId
    ) {
        return String.valueOf(accountId)
            + '-'
            + quarterKey
            + '-QUARTERLY-REVIEW-'
            + String.valueOf(assigneeId);
    }

    private static Set<String> getExistingAutomationKeys(
        Set<String> automationKeys
    ) {
        Set<String> existingKeys = new Set<String>();
        
        if (automationKeys.isEmpty()) {
            return existingKeys;
        }
        for (Task task : [
            SELECT Id,CallDisposition 
            FROM Task
            WHERE CallDisposition  IN :automationKeys
        ]) {
            if (String.isNotBlank(task.CallDisposition )) {
                existingKeys.add(
                    task.CallDisposition 
                );
            }
        }
        
        return existingKeys;
    }

    private static Task buildQuarterlyTask(
        Account acc,
        Id assigneeId,
        QuarterInfo quarterInfo,
        String automationKey
    ) {

        Task task = new Task();
        task.OwnerId = assigneeId;
        task.WhatId = acc.Id;
        task.Subject = 'Quarterly Account Strategy Review – ' + acc.Name;
        task.Priority = 'Medium';
        task.Status = 'Not Started';
        task.ActivityDate = getReviewDueDate(quarterInfo.quarterEnd);
        task.CallDisposition  = automationKey;
        task.Description = buildTaskDescription(acc, quarterInfo);

        return task;
    }

    private static String buildTaskDescription(
        Account acc,
        QuarterInfo quarterInfo
    ) {

        List<String> details = new List<String>();

        details.add('Account Name: ' + acc.Name);
        details.add('Account Owner: ' + (acc.Owner != null ? acc.Owner.Name: 'N/A'));
        details.add('Account Status: ' + String.valueOf(acc.Status__c));
        details.add('Last Activity Date: ' + String.valueOf(acc.LastActivityDate));
        details.add('Quarter: ' + quarterInfo.quarterKey);
        details.add('Annual Revenue: ' + String.valueOf(acc.AnnualRevenue));
        return String.join(details, '\n');
    }

    private static Date getReviewDueDate(
        Date quarterEnd
    ) {
        Date dueDate = quarterEnd;
        while (isWeekend(dueDate)) {
            dueDate = dueDate.addDays(-1);
        }
        return dueDate;
    }

    private static Boolean isWeekend(Date inputDate) { 
        Datetime dt = Datetime.newInstance(inputDate, Time.newInstance(0,0,0,0));
        String dayName = dt.format('EEE');
        return dayName == 'Sat' || dayName == 'Sun';
    }
}