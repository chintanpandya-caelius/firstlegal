/*
* @Author : Rahul Bhavsar
* @Created Date : 18/09/26
* @Description : Batch class to identify Annual Portfolio Growth Opportunities and generate new revenues 
* @Story Number : 5159
*/
global with sharing class PortfolioGrowthOpportunityBatch
    implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        return 
        Database.getQueryLocator([
            SELECT Id, Name, OwnerId, Status__c, Terms__c
                FROM Account
                WHERE IsDeleted = FALSE
                AND Status__c = 'Active'
                AND Terms__c = TRUE
        ]);
    }

    global void execute(
        Database.BatchableContext bc,
        List<Account> accounts
    ) {
        if (accounts == null || accounts.isEmpty()) {return;}
        PortfolioGrowthOpportunityHelper.processAccounts(accounts);
    }

    global void finish(Database.BatchableContext bc) {
        System.debug(
            LoggingLevel.INFO,
            'Portfolio Growth Opportunity batch completed.'
        );
        String termValue1 = 'Assignment 1';
        String termValue2 = 'Assignment 2';
        String termValue3 = 'Assignment 3';
        String termValue4 = 'Assignment 4';
        String termValue5 = 'Assignment 5';
        String termValue6 = 'Assignment 6';
    }
}