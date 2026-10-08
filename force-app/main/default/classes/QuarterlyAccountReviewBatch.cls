/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Batch class for generating recurring quarterly review Tasks for Account Owners and 
                    their direct managers to support account strategy alignment and performance reviews
* @Story Number : 5450
*/


global class QuarterlyAccountReviewBatch 
    implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT Id, Name, OwnerId, Owner.Name, Owner.ManagerId, Owner.Manager.Name,
                    Status__c, LastActivityDate, AnnualRevenue
                    FROM Account WHERE IsDeleted = FALSE
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<Account> accounts
    ) {
        AccountReviewService.createQuarterlyTasks(accounts);
    }

    global void finish(Database.BatchableContext bc) {
    }
}