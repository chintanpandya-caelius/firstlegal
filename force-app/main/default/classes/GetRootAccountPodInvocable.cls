public without sharing class GetRootAccountPodInvocable {

    public class Request {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    public class Response {
        @InvocableVariable
        public String assignedPodApiName;
        @InvocableVariable
        public String clientSpecificEmail;
    }

    @InvocableMethod(
        label='Get Root Account Assigned POD'
        description='Given an Account Id, walks the parent root Account and returns its Assigned_POD__c value'
    )
    public static List<Response> execute(List<Request> requests) {
        
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) return responses;

        Set<Id> startAccountIds = new Set<Id>();
        for (Request req : requests) {
            if (req.accountId != null) startAccountIds.add(req.accountId);
        }

        Map<Id, Account> hierarchyMap = AccountHierarchyUtil.buildHierarchyMap(
            startAccountIds,
            new Set<String>{ 'Assigned_POD__c', 'Client_Specific_Email__c' }
        );

        for (Request req : requests) {
            Response res = new Response();

            if (req.accountId != null) {
                Id rootId = AccountHierarchyUtil.getRootParentId(req.accountId, hierarchyMap);
                Account rootAcc = (rootId != null) ? hierarchyMap.get(rootId) : null;

                if (rootAcc != null) {
                    res.assignedPodApiName = toApiName(rootAcc.Assigned_POD__c);
                    res.clientSpecificEmail = rootAcc.Client_Specific_Email__c;
                }
            }
            responses.add(res);
        }
        return responses;
    }

    private static String toApiName(String podValue) {
        if (String.isBlank(podValue)) return null;
        return podValue.trim().replaceAll('\\s+', '_');
    }
}