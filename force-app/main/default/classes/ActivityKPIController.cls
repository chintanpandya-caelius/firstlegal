public with sharing class ActivityKPIController {

    public class KPIRow {
        @AuraEnabled public String activityType { get; set; }
        @AuraEnabled public Integer currentTouchPoints { get; set; }
        @AuraEnabled public Integer targetGoal { get; set; }
        @AuraEnabled public Integer remainingTouchPoints { get; set; }
        @AuraEnabled public Integer progressPercent { get; set; }
        @AuraEnabled public String displayProgress { get; set; }
        @AuraEnabled public String statusLabel { get; set; }
        @AuraEnabled public String statusClass { get; set; }
        
        @AuraEnabled public Boolean isEventTile { get; set; }
        @AuraEnabled public Integer virtualCount { get; set; }
        @AuraEnabled public Integer inPersonCount { get; set; }
        
        @AuraEnabled public Integer ytdCount { get; set; }

        public KPIRow(String type, Integer actual, Integer goal, Integer ytdActual) {
            this(type, actual, goal, false, 0, 0, ytdActual);
        }

        public KPIRow(String type, Integer actual, Integer goal, Boolean isEvent, Integer virtualCnt, Integer inPersonCnt, Integer ytdActual) {
            this.activityType = type;
            this.currentTouchPoints = actual;
            this.targetGoal = goal;
            this.isEventTile = isEvent;
            this.virtualCount = virtualCnt;
            this.inPersonCount = inPersonCnt;
            this.ytdCount = ytdActual;

            if (goal > 0) {
                this.remainingTouchPoints = Math.max(goal - actual, 0);
                Decimal pct = ((Decimal)actual / goal) * 100;
                this.progressPercent = (Integer)pct.round(System.RoundingMode.HALF_UP);
                this.displayProgress = this.progressPercent + '%';

                if (this.progressPercent >= 100) {
                    this.statusLabel = 'Target Met';
                    this.statusClass = 'slds-text-color_success slds-text-title_bold';
                } else if (this.progressPercent >= 75) {
                    this.statusLabel = 'On Track';
                    this.statusClass = 'slds-text-color_success';
                } else if (this.progressPercent >= 50) {
                    this.statusLabel = 'Needs Attention';
                    this.statusClass = 'slds-text-color_warning';
                } else {
                    this.statusLabel = 'Behind Target';
                    this.statusClass = 'slds-text-color_error';
                }
            } else {
                this.remainingTouchPoints = 0;
                this.progressPercent = 0;
                this.displayProgress = 'N/A';
                this.statusLabel = 'No Target Set';
                this.statusClass = 'slds-text-color_weak';
            }
        }
    }

    public class KPIResponse {
        @AuraEnabled public String reportingPeriod { get; set; }
        @AuraEnabled public List<KPIRow> kpiRows { get; set; }

        public KPIResponse(String period, List<KPIRow> rows) {
            this.reportingPeriod = period;
            this.kpiRows = rows;
        }
    }

    @AuraEnabled(cacheable=true)
    public static KPIResponse getMyKPI(Id recordId, String selectedPeriod) {
        Id currentUserId = UserInfo.getUserId();
        String period = String.isNotBlank(selectedPeriod) ? selectedPeriod : 'Monthly';

        Integer emailGoal = 0, callGoal = 0, taskGoal = 0, eventGoal = 0;

        // Fetch active KPI Goal record matching User, Period, and Current Date Range
        List<KPI_Goal__c> goals = [
            SELECT Email_Goal__c, Call_Goal__c, Task_Goal__c, Event_Goal__c, Reporting_Period__c
            FROM KPI_Goal__c 
            WHERE (User__c = :currentUserId OR User__c = null)
              AND Active__c = true
              AND Reporting_Period__c = :period
              AND (Effective_From__c <= TODAY OR Effective_From__c = null)
              AND (Effective_To__c >= TODAY OR Effective_To__c = null)
            WITH USER_MODE
            ORDER BY User__c NULLS LAST, CreatedDate DESC 
            LIMIT 1
        ];

        if (!goals.isEmpty()) {
            KPI_Goal__c activeGoal = goals[0];
            emailGoal = activeGoal.Email_Goal__c != null ? (Integer)activeGoal.Email_Goal__c : 0;
            callGoal = activeGoal.Call_Goal__c != null ? (Integer)activeGoal.Call_Goal__c : 0;
            taskGoal = activeGoal.Task_Goal__c != null ? (Integer)activeGoal.Task_Goal__c : 0;
            eventGoal = activeGoal.Event_Goal__c != null ? (Integer)activeGoal.Event_Goal__c : 0;
        }

        Boolean isAccountContext = (recordId != null && recordId.getSObjectType().getDescribe().getName() == 'Account');
        Set<Id> accountRelatedWhatIds = new Set<Id>();
        Set<Id> accountRelatedWhoIds = new Set<Id>();

        if (isAccountContext) {
            accountRelatedWhatIds.add(recordId);
            for (Contact con : [SELECT Id FROM Contact WHERE AccountId = :recordId WITH USER_MODE LIMIT 2000]) accountRelatedWhoIds.add(con.Id);
            for (Opportunity opp : [SELECT Id FROM Opportunity WHERE AccountId = :recordId WITH USER_MODE LIMIT 2000]) accountRelatedWhatIds.add(opp.Id);
            for (Lead ld : [SELECT Id FROM Lead WHERE ConvertedAccountId = :recordId WITH USER_MODE LIMIT 2000]) accountRelatedWhoIds.add(ld.Id);
        }

        // Fetch Actual Touch Counts
        Integer emailCount = isAccountContext ? 
            [SELECT COUNT() FROM EmailMessage WHERE RelatedToId IN :accountRelatedWhatIds WITH USER_MODE] :
            [SELECT COUNT() FROM EmailMessage WITH USER_MODE];

        Integer callCount = isAccountContext ? 
            [SELECT COUNT() FROM Task WHERE (WhatId IN :accountRelatedWhatIds OR WhoId IN :accountRelatedWhoIds) AND TaskSubtype = 'Call' WITH USER_MODE] :
            [SELECT COUNT() FROM Task WHERE TaskSubtype = 'Call' WITH USER_MODE];

        Integer taskCount = isAccountContext ? 
            [SELECT COUNT() FROM Task WHERE (WhatId IN :accountRelatedWhatIds OR WhoId IN :accountRelatedWhoIds) AND (TaskSubtype = null OR TaskSubtype != 'Call') WITH USER_MODE] :
            [SELECT COUNT() FROM Task WHERE (TaskSubtype = null OR TaskSubtype != 'Call') WITH USER_MODE];

        List<Event> eventsList = isAccountContext ? 
            [SELECT Id, Event_Type__c, Type, Event_Subtype__c 
             FROM Event 
             WHERE (WhatId IN :accountRelatedWhatIds OR WhoId IN :accountRelatedWhoIds) 
             AND (Event_Type__c = 'Meeting' OR Type = 'Meeting') WITH USER_MODE] :
            [SELECT Id, Event_Type__c, Type, Event_Subtype__c 
             FROM Event 
             WHERE (Event_Type__c = 'Meeting' OR Type = 'Meeting') WITH USER_MODE];

        Integer virtualEvents = 0;
        Integer inPersonEvents = 0;

        for (Event evt : eventsList) {
            String subtypeVal = evt.Event_Subtype__c != null ? evt.Event_Subtype__c.trim() : '';
            if (subtypeVal.equalsIgnoreCase('Virtual Meeting') || subtypeVal.toLowerCase().contains('virtual')) {
                virtualEvents++;
            } else {
                inPersonEvents++;
            }
        }

        Integer eventCount = eventsList.size();

        // Calculate YTD Actual Counts (Current Year)
        Datetime ytdStartDateTime = Datetime.newInstance(Date.today().year(), 1, 1, 0, 0, 0);
        Date ytdStartDate = Date.newInstance(Date.today().year(), 1, 1);

        Integer emailYtd = isAccountContext ? 
            [SELECT COUNT() FROM EmailMessage WHERE RelatedToId IN :accountRelatedWhatIds AND CreatedDate >= :ytdStartDateTime WITH USER_MODE] :
            [SELECT COUNT() FROM EmailMessage WHERE CreatedDate >= :ytdStartDateTime WITH USER_MODE];

        Integer callYtd = isAccountContext ? 
            [SELECT COUNT() FROM Task WHERE (WhatId IN :accountRelatedWhatIds OR WhoId IN :accountRelatedWhoIds) AND TaskSubtype = 'Call' AND (ActivityDate >= :ytdStartDate OR CreatedDate >= :ytdStartDateTime) WITH USER_MODE] :
            [SELECT COUNT() FROM Task WHERE TaskSubtype = 'Call' AND (ActivityDate >= :ytdStartDate OR CreatedDate >= :ytdStartDateTime) WITH USER_MODE];

        Integer taskYtd = isAccountContext ? 
            [SELECT COUNT() FROM Task WHERE (WhatId IN :accountRelatedWhatIds OR WhoId IN :accountRelatedWhoIds) AND (TaskSubtype = null OR TaskSubtype != 'Call') AND (ActivityDate >= :ytdStartDate OR CreatedDate >= :ytdStartDateTime) WITH USER_MODE] :
            [SELECT COUNT() FROM Task WHERE (TaskSubtype = null OR TaskSubtype != 'Call') AND (ActivityDate >= :ytdStartDate OR CreatedDate >= :ytdStartDateTime) WITH USER_MODE];

        Integer eventYtd = isAccountContext ? 
            [SELECT COUNT() FROM Event WHERE (WhatId IN :accountRelatedWhatIds OR WhoId IN :accountRelatedWhoIds) AND (Event_Type__c = 'Meeting' OR Type = 'Meeting') AND (ActivityDate >= :ytdStartDate OR CreatedDate >= :ytdStartDateTime) WITH USER_MODE] :
            [SELECT COUNT() FROM Event WHERE (Event_Type__c = 'Meeting' OR Type = 'Meeting') AND (ActivityDate >= :ytdStartDate OR CreatedDate >= :ytdStartDateTime) WITH USER_MODE];

        // Construct Response Rows
        List<KPIRow> rows = new List<KPIRow>();
        rows.add(new KPIRow('Emails', emailCount, emailGoal, emailYtd));
        rows.add(new KPIRow('Calls', callCount, callGoal, callYtd));
        rows.add(new KPIRow('Tasks', taskCount, taskGoal, taskYtd));
        rows.add(new KPIRow('Events', eventCount, eventGoal, true, virtualEvents, inPersonEvents, eventYtd));

        Integer totalActual = emailCount + callCount + taskCount + eventCount;
        Integer totalGoal = emailGoal + callGoal + taskGoal + eventGoal;
        Integer totalYtd = emailYtd + callYtd + taskYtd + eventYtd;
        rows.add(new KPIRow('TOTAL', totalActual, totalGoal, totalYtd));

        return new KPIResponse(period, rows);
    }
}