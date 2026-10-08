public with sharing class OpportunityRevenueValidationHandler {

    private static final Set<String> STANDARD_TYPES = new Set<String>{
        'New Logo',
        'Cross Sell',
        'Portfolio Growth'
    };

    private static final Set<String> PROJECT_TYPES = new Set<String>{
        'Class Action',
        'Matter Specific Project',
        'Worker\'s Comp'
    };

    private static final Set<String> PROJECT_VALID_STAGES = new Set<String>{
        'Discovery',
        'Proposal',
        'Negotiation',
        'Closed Won'
    };

    private static final Set<String> VALID_SERVICE_LINES = new Set<String>{
        'Court & Process',
        'Depositions',
        'Digital',
        'E-Discovery',
        'Investigations',
        'Records'
    };

    public static void handleBeforeSave(
        List<Opportunity> newOpps,
        Map<Id, Opportunity> oldMap
    ) {
        if (newOpps == null || newOpps.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        Set<Integer> fiscalYears = new Set<Integer>();
        Set<Id> transactionOpportunityIds = new Set<Id>();

        for (Opportunity opp : newOpps) {
            if (opp.Id != null) {
                transactionOpportunityIds.add(opp.Id);
            }

            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }

            if (opp.CloseDate != null) {
                fiscalYears.add(opp.CloseDate.year());
            }
        }

        // Revenue Type and Close Date are required.
        for (Opportunity opp : newOpps) {
            if (String.isBlank(opp.Revenue_Type__c)) {
                opp.Revenue_Type__c.addError('Revenue Type is required.');
            }

            if (opp.CloseDate == null) {
                opp.CloseDate.addError(
                    'Close Date is required to determine the fiscal year.'
                );
            }
        }

        if (accountIds.isEmpty() || fiscalYears.isEmpty()) {
            return;
        }

        Date minimumFYStart;
        Date maximumFYEnd;

        for (Integer yearValue : fiscalYears) {
            Date yearStart = Date.newInstance(yearValue, 1, 1);
            Date yearEnd = Date.newInstance(yearValue, 12, 31);

            if (minimumFYStart == null || yearStart < minimumFYStart) {
                minimumFYStart = yearStart;
            }

            if (maximumFYEnd == null || yearEnd > maximumFYEnd) {
                maximumFYEnd = yearEnd;
            }
        }

        List<Opportunity> existingOpps = new List<Opportunity>();

        if (minimumFYStart != null && maximumFYEnd != null) {
            existingOpps = [
                SELECT
                    Id,
                    AccountId,
                    Revenue_Type__c,
                    Service_Line__c,
                    Matter_Case_Number__c,
                    StageName,
                    CloseDate
                FROM Opportunity
                WHERE AccountId IN :accountIds
                AND CloseDate >= :minimumFYStart
                AND CloseDate <= :maximumFYEnd
            ];
        }

        List<Opportunity> databaseRelevantOpps = new List<Opportunity>();

        for (Opportunity existing : existingOpps) {
            if (existing.Id != null && transactionOpportunityIds.contains(existing.Id)) {
                continue;
            }

            databaseRelevantOpps.add(existing);
        }

        List<Opportunity> transactionRelevantOpps =new List<Opportunity>();

        for (Opportunity opp : newOpps) {
            if (opp.AccountId == null || opp.CloseDate == null) {
                continue;
            }

            if ((STANDARD_TYPES.contains(opp.Revenue_Type__c) || PROJECT_TYPES.contains(opp.Revenue_Type__c)) && String.isBlank(opp.Service_Line__c)){
                opp.Service_Line__c.addError('Service Line is required for this Revenue Type.');
                continue;
            }

            if (!String.isBlank(opp.Service_Line__c) & !VALID_SERVICE_LINES.contains(opp.Service_Line__c)){
                opp.Service_Line__c.addError('Invalid Service Line. The Service Line must be one of: Court & Process, Depositions, Digital, E-Discovery, Investigations, or Records.');
                continue;
            }

            Integer oppFiscalYear = opp.CloseDate.year();

            List<Opportunity> relevantOpps = new List<Opportunity>();
            relevantOpps.addAll(databaseRelevantOpps);
            relevantOpps.addAll(transactionRelevantOpps);

            if (STANDARD_TYPES.contains(opp.Revenue_Type__c)) {
                validateStandardRevenueType(opp,relevantOpps,oppFiscalYear);
            }

            if (PROJECT_TYPES.contains(opp.Revenue_Type__c)) {
                validateProjectRevenueType(opp,relevantOpps,oppFiscalYear);
            }

            transactionRelevantOpps.add(opp);
        }
    }

    private static void validateStandardRevenueType(Opportunity opp,List<Opportunity> relevantOpps,Integer oppFiscalYear) {
        // Standard Revenue Types cannot have a Matter/Case Number.
        if (String.isNotBlank(opp.Matter_Case_Number__c)) {
            opp.Matter_Case_Number__c.addError('Matter/Case Number is prohibited for standard revenue types.');
            return;
        }

        Integer standardOppCount = 0;
        Boolean hasNewLogoInFY = false;
        Boolean hasPortfolioGrowthInFY = false;
        Boolean hasSameServiceLineNewLogo = false;
        Boolean hasSameServiceLinePortfolioGrowth = false;
        Boolean hasSameServiceLineCrossSell = false;

        for (Opportunity existing : relevantOpps) {
            if (opp.Id != null && existing.Id != null && existing.Id == opp.Id) {
                continue;
            }

            if (existing.AccountId != opp.AccountId) {
                continue;
            }

            if (existing.CloseDate == null ||existing.CloseDate.year() != oppFiscalYear) {
                continue;
            }

            if (!STANDARD_TYPES.contains(existing.Revenue_Type__c)) {
                continue;
            }

            standardOppCount++;

            if (existing.Revenue_Type__c == 'New Logo') {
                hasNewLogoInFY = true;
            }

            if (existing.Revenue_Type__c == 'Portfolio Growth') {
                hasPortfolioGrowthInFY = true;
            }

            if (existing.Service_Line__c == opp.Service_Line__c) {
                if (existing.Revenue_Type__c == 'New Logo') {
                    hasSameServiceLineNewLogo = true;
                }

                if (existing.Revenue_Type__c == 'Portfolio Growth') {
                    hasSameServiceLinePortfolioGrowth = true;
                }

                if (existing.Revenue_Type__c == 'Cross Sell') {
                    hasSameServiceLineCrossSell = true;
                }
            }
        }

        // New Logo is only allowed when no standard opportunity exists in the FY.
        if (opp.Revenue_Type__c == 'New Logo') {
            if (hasPortfolioGrowthInFY) {
                opp.Revenue_Type__c.addError('One or more Portfolio Growth opportunities exist on this account for this fiscal year, please change to Revenue Type to Cross Sell.');
                return;
            }

            if (hasNewLogoInFY) {
                opp.Revenue_Type__c.addError('A New Logo opportunity already exists on this account for this fiscal year, please change to Revenue Type to Cross Sell.');
                return;
            }

            if (standardOppCount > 0) {
                opp.Revenue_Type__c.addError('One or more standard Revenue Type opportunities already exist on this account for this fiscal year, please change to Revenue Type to Cross Sell.');
                return;
            }

            if (hasSameServiceLineNewLogo) {
                opp.Service_Line__c.addError('A New Logo opportunity already exists on this account for this service line for this fiscal year.');
                return;
            }
        }

        // Cross Sell cannot reuse an existing standard Service Line in the FY.
        if (opp.Revenue_Type__c == 'Cross Sell') {
            if (hasSameServiceLineNewLogo || hasSameServiceLinePortfolioGrowth || hasSameServiceLineCrossSell) {
                opp.Service_Line__c.addError('An opportunity already exists on this account for this service line for this fiscal year, please update the Service Line or cancel Save.');
                return;
            }

            if (standardOppCount >= 6) {
                opp.addError('The maximum of six standard Revenue Type opportunities has already been reached for this account for this fiscal year.');
                return;
            }
        }

        // Portfolio Growth cannot coexist with New Logo in the FY.
        if (opp.Revenue_Type__c == 'Portfolio Growth') {
            if (hasNewLogoInFY) {
                opp.Revenue_Type__c.addError('A New Logo opportunity already exists on this account for this fiscal year, please change to Revenue Type to Cross Sell.');
                return;
            }

            if (hasSameServiceLinePortfolioGrowth) {
                opp.Revenue_Type__c.addError('A Portfolio Growth opportunity already exists on this account for this service line for this fiscal year, please update the Service Line or Revenue Type, or cancel Save.');
                return;
            }

            if (standardOppCount >= 6) {
               opp.addError('The maximum of six standard Revenue Type opportunities has already been reached for this account for this fiscal year.');
                return;
            }
        }
    }

    private static void validateProjectRevenueType(Opportunity opp,List<Opportunity> relevantOpps,Integer oppFiscalYear) {
        // Matter/Case Number is required from Discovery through Closed Won.
        if (PROJECT_VALID_STAGES.contains(opp.StageName) &&String.isBlank(opp.Matter_Case_Number__c)) {
            opp.Matter_Case_Number__c.addError('Matter/Case Number is required for this revenue type in stage Discovery or later.');
            return;
        }

        if (!PROJECT_VALID_STAGES.contains(opp.StageName) ||String.isBlank(opp.Matter_Case_Number__c)) {
            return;
        }

        String newMatterNumber = opp.Matter_Case_Number__c.trim();

        for (Opportunity existing : relevantOpps) {
            if (opp.Id != null && existing.Id != null && existing.Id == opp.Id) {
                continue;
            }

            if (existing.AccountId != opp.AccountId) {
                continue;
            }

            if (existing.CloseDate == null ||existing.CloseDate.year() != oppFiscalYear) {
                continue;
            }

            if (!PROJECT_TYPES.contains(existing.Revenue_Type__c)) {
                continue;
            }

            if (!PROJECT_VALID_STAGES.contains(existing.StageName)) {
                continue;
            }

            if (String.isBlank(existing.Matter_Case_Number__c)) {
                continue;
            }

            String existingMatterNumber =
                existing.Matter_Case_Number__c.trim();

            // Duplicate is based on Account + FY + Matter/Case Number + Service Line.
            if (newMatterNumber.equalsIgnoreCase(existingMatterNumber) && existing.Service_Line__c == opp.Service_Line__c) {
                opp.addError('This Matter/Case Number is already in use for this service line on this account. Please update the Matter/Case Number or Service Line, or cancel Save.');
                return;
            }
        }
    }
}