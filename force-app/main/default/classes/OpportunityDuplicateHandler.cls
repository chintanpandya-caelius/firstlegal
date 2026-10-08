public with sharing class OpportunityDuplicateHandler {

    public static void checkDuplicates(List<Opportunity> newOpportunities){

        Set<Id> accountIds = new Set<Id>();
        Set<String> oppNames = new Set<String>();

        for(Opportunity opp : newOpportunities){

            if(opp.AccountId != null)
                accountIds.add(opp.AccountId);

            if(String.isNotBlank(opp.Name))
                oppNames.add(opp.Name.trim().toLowerCase());
        }

        List<Opportunity> existingOpps = [
            SELECT Id,
                   Name,
                   AccountId,
                   Amount,
                   CloseDate,
                   StageName
            FROM Opportunity
            WHERE AccountId IN :accountIds
        ];

        for(Opportunity newOpp : newOpportunities){

            for(Opportunity oldOpp : existingOpps){

                if(newOpp.Id == oldOpp.Id)
                    continue;

                Boolean duplicate = false;

                // Rule 1
                if(newOpp.AccountId == oldOpp.AccountId &&
                   normalize(newOpp.Name) == normalize(oldOpp.Name))
                {
                    duplicate = true;
                }

                // Rule 2
                else if(newOpp.AccountId == oldOpp.AccountId &&
                        newOpp.CloseDate == oldOpp.CloseDate &&
                        newOpp.Amount == oldOpp.Amount)
                {
                    duplicate = true;
                }

                // Rule 3
                else if(newOpp.AccountId == oldOpp.AccountId &&
                        normalize(newOpp.Name) == normalize(oldOpp.Name) &&
                        newOpp.CloseDate == oldOpp.CloseDate)
                {
                    duplicate = true;
                }

                if(duplicate){

                    newOpp.addError(
                        'Possible duplicate Opportunity detected.\n\n'
                        + 'Existing Opportunity: '
                        + oldOpp.Name
                        + '\nStage: '
                        + oldOpp.StageName
                        + '\nClose Date: '
                        + oldOpp.CloseDate
                    );
                }

            }

        }

    }

    private static String normalize(String value){

        if(String.isBlank(value))
            return '';

        return value.trim().toLowerCase();
    }
}