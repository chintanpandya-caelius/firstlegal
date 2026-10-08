/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Helper for the Quartelry Task creation and high priority task creation batch, 
                    to get the latest configuration from metedata
* @Story Number : 5450
*/

public with sharing class AccountAutomationConfig {

    public Boolean quarterlyReviewEnabled;
    public Boolean inactivityMonitoringEnabled;
    public Integer inactivityDays;
    public String reviewTaskPriority;
    public String inactivityTaskPriority;
    public Integer fiscalYearStartMonth;

    public static AccountAutomationConfig getConfig() {

        Account_Automation_Config__mdt config = Account_Automation_Config__mdt.getInstance('Quarterly_Task_Creation');
        AccountAutomationConfig result = new AccountAutomationConfig();

        if (config == null) {
            result.setDefaults();
            return result;
        }

        result.quarterlyReviewEnabled = config.Quarterly_Review_Enabled__c;
        result.inactivityMonitoringEnabled = config.Inactivity_Monitoring_Enabled__c;
        result.inactivityDays = config.Inactivity_Days__c != null ? Integer.valueOf(config.Inactivity_Days__c) : 60;
        result.reviewTaskPriority = String.isNotBlank(config.Review_Task_Priority__c) ? config.Review_Task_Priority__c: 'Medium';
        result.inactivityTaskPriority = String.isNotBlank(config.Inactivity_Task_Priority__c)? config.Inactivity_Task_Priority__c : 'High';
        result.fiscalYearStartMonth = config.Fiscal_Year_Start_Month__c != null ? Integer.valueOf(config.Fiscal_Year_Start_Month__c): 1;

        return result;
    }

    private void setDefaults() {
        quarterlyReviewEnabled = true;
        inactivityMonitoringEnabled = true;
        inactivityDays = 60;
        reviewTaskPriority = 'Medium';
        inactivityTaskPriority = 'High';
        fiscalYearStartMonth = 1;
    }
}