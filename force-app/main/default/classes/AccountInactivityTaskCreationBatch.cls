global with sharing class AccountInactivityTaskCreationBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(
        Database.BatchableContext bc
    ) {
        return Database.getQueryLocator([ SELECT Id, Name, OwnerId, Owner.Name, Status__c, AnnualRevenue
               								FROM Account WHERE IsDeleted = FALSE]);
    }

    global void execute(Database.BatchableContext bc, List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;}
        
        AccountAutomationConfig config = AccountAutomationConfig.getConfig();
        AccountInactivityService.processAccounts(accounts, config);
    }

    global void finish(Database.BatchableContext bc) 
    { 
        System.debug( 'Account inactivity batch completed.');
    }
}