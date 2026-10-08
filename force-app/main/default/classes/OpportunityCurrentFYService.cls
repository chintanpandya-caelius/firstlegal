public without sharing class OpportunityCurrentFYService {
    public static void stampCurrentFY(List<Opportunity> opps) {
        Integer currentYear = Date.today().year();
        for (Opportunity o : opps) {
            o.Is_Current_FY__c = (o.CloseDate != null && o.CloseDate.year() == currentYear);
        }
    }
}