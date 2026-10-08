public class CaseTriggerHandler {
	
    private static Set<String> closedStatuses;

    public static void captureCaseClosure(List<Case> newCases, Map<Id, Case> oldCasesMap) {
        if (closedStatuses == null) {
            closedStatuses = new Set<String>();
            for (CaseStatus validStatus : [SELECT MasterLabel FROM CaseStatus WHERE IsClosed = true]) {
                closedStatuses.add(validStatus.MasterLabel);
            }
        }

        for (Case newCase : newCases) {
            Case oldCase = (oldCasesMap != null) ? oldCasesMap.get(newCase.Id) : null;
            
            Boolean isNowClosed = closedStatuses.contains(newCase.Status);
            Boolean wasClosed = (oldCase != null) && closedStatuses.contains(oldCase.Status);

            if (isNowClosed && !wasClosed) {
                newCase.Closure_DateTime__c = System.now();
            }
            //Case is reopened
            else if (!isNowClosed && wasClosed) {
                newCase.Closure_DateTime__c = null;
            }
        }
    }

}