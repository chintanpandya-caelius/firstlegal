public with sharing class DuplicateBypassLeadUpdater {

    public class Request {
        @InvocableVariable(required=true)
        public Lead leadRecord;
    }

    @InvocableMethod(label='Update Lead Bypassing Duplicate Rules')
    public static void updateLeads(List<Request> requests) {

        List<Lead> leadsToUpdate = new List<Lead>();

        for (Request req : requests) {
            if (req != null && req.leadRecord != null) {
                leadsToUpdate.add(req.leadRecord);
            }
        }

        if (leadsToUpdate.isEmpty()) {
            return;
        }

        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.allowSave = true;
        dmlOptions.optAllOrNone = false;

        Database.update(leadsToUpdate, dmlOptions);
    }
}