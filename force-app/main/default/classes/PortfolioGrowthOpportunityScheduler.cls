/*
* @Author : Rahul Bhavsar
* @Created Date : 18/09/26
* @Description : Scheduler class to schedule PortfolioGrowthOpportunityBatch 
* @Story Number : 5159
*/
global with sharing class PortfolioGrowthOpportunityScheduler
    implements Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(
            new PortfolioGrowthOpportunityBatch(),
            200
        );
    }
}