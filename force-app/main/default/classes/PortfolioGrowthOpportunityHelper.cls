/*
* @Author : Rahul Bhavsar
* @Created Date : 18/09/26
* @Description : Helper class for PortfolioGrowthOpportunityBatch, to identify successfull opportunities and 
                generate new opportunities
* @Story Number : 5159
*/
public with sharing class PortfolioGrowthOpportunityHelper {

    public static void processAccounts(List<Account> accounts) {

        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accounts) {
            if (acc.Id != null) {
                accountIds.add(acc.Id);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Integer currentYear = Date.today().year();
        Date currentFiscalYearStart = Date.newInstance(currentYear, 1, 1);
        Date currentFiscalYearEnd = Date.newInstance(currentYear, 12, 31);
        Date previousFiscalYearStart = Date.newInstance(currentYear - 1, 7, 1);
        Date previousFiscalYearEnd = Date.newInstance(currentYear - 1, 12, 31);

        List<Opportunity> qualifyingOpportunities = [
            SELECT Id, Name, AccountId, OwnerId, StageName, Revenue_Type__c, Service_Line__c, Estimated_Monthly_Revenue__c, Estimated_Annual_Revenue__c, CloseDate
            FROM Opportunity
            WHERE AccountId IN :accountIds
              AND Revenue_Type__c IN ( 'New Logo', 'Cross Sell', 'Portfolio Growth')
              AND StageName = 'Closed Won'
              AND CloseDate >= :previousFiscalYearStart
              AND CloseDate <= :previousFiscalYearEnd
        ];

        if (qualifyingOpportunities.isEmpty()) {
            return;
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Name, OwnerId
                FROM Account
                WHERE Id IN :accountIds
        ]);

        Map<String, Decimal> revenueByAccountServiceLine = new Map<String, Decimal>();
        for (Opportunity opp : qualifyingOpportunities) {
            if (opp.AccountId == null ||
                opp.Service_Line__c == null) {
                continue;
            }

            String key = String.valueOf(opp.AccountId) + '|' + opp.Service_Line__c;
            Decimal previousRevenue = 0;

            if (opp.Estimated_Annual_Revenue__c != null) { 
                previousRevenue = opp.Estimated_Annual_Revenue__c;
            }
            if (!revenueByAccountServiceLine.containsKey(key)) {
                revenueByAccountServiceLine.put(key,0);
            }
            revenueByAccountServiceLine.put(key, revenueByAccountServiceLine.get(key) + previousRevenue);
        }


        if (revenueByAccountServiceLine.isEmpty()) {
            return;
        }

        Set<String> existingOpportunityKeys = new Set<String>();
        for (Opportunity existingOpp : [
            SELECT Id, AccountId, Service_Line__c, Revenue_Type__c, Estimated_Start_Date__c, Estimated_End_Date__c
            FROM Opportunity
            WHERE AccountId IN :accountIds
              AND Revenue_Type__c = 'Portfolio Growth'
              AND Estimated_Start_Date__c = :currentFiscalYearStart
              AND Estimated_End_Date__c = :currentFiscalYearEnd
        ]) {

            if (existingOpp.AccountId == null ||
                existingOpp.Service_Line__c == null) {
                continue;
            }

            String key = String.valueOf(existingOpp.AccountId) + '|' + existingOpp.Service_Line__c;
            existingOpportunityKeys.add(key);
        }
        List<Opportunity> opportunitiesToCreate = new List<Opportunity>();
        Set<String> newOpportunityKeys = new Set<String>();
        
        for (Opportunity sourceOpp : qualifyingOpportunities) {
            if (sourceOpp.AccountId == null ||
                sourceOpp.Service_Line__c == null) {
                continue;
            }
            Account account = accountMap.get(sourceOpp.AccountId);
            if (account == null) {
                continue;
            }

            String key = String.valueOf(sourceOpp.AccountId) + '|' + sourceOpp.Service_Line__c;

            if (existingOpportunityKeys.contains(key)) {
                continue;
            }
            if (newOpportunityKeys.contains(key)) {
                continue;
            }
            
            Decimal previousYearRevenue = revenueByAccountServiceLine.get(key);
            if (previousYearRevenue == null ||
                previousYearRevenue <= 0) {
                continue;
            }
            
            Decimal estimatedMonthlyRevenue;
            Decimal estimatedAnnualRevenue;


            if (sourceOpp.Service_Line__c == 'E-Discovery') {
                estimatedAnnualRevenue = previousYearRevenue;
                estimatedMonthlyRevenue = previousYearRevenue / 12;

            } else {
                estimatedAnnualRevenue = previousYearRevenue * 1.10;
                estimatedMonthlyRevenue = estimatedAnnualRevenue / 12;
            }

            Opportunity newOpp = new Opportunity();
            newOpp.Name = account.Name + ' - ' + sourceOpp.Service_Line__c + ' - Portfolio Growth ' + currentYear;
            newOpp.AccountId = sourceOpp.AccountId;
            newOpp.Revenue_Type__c = 'Portfolio Growth';
            newOpp.StageName = 'Qualification';
            newOpp.Order_Type__c = 'Terms';
            newOpp.Estimated_Start_Date__c = currentFiscalYearStart;
            newOpp.Estimated_End_Date__c = currentFiscalYearEnd;
            newOpp.CloseDate = Date.newInstance(currentYear, 1, 31);
            newOpp.Estimated_Monthly_Revenue__c = estimatedMonthlyRevenue;
            newOpp.Estimated_Annual_Revenue__c = estimatedAnnualRevenue;
            newOpp.Service_Line__c = sourceOpp.Service_Line__c;
            newOpp.OwnerId =account.OwnerId;
            opportunitiesToCreate.add(newOpp);
            newOpportunityKeys.add(key);
        }

        if (!opportunitiesToCreate.isEmpty()) {
            insert opportunitiesToCreate;
        }
    }
}