@isTest
public class GetRootAccountPodInvocableTest {
    
    @isTest
    static void GetRootAccountPodInvocableTest_m1(){
        
        Account act = new Account();
        act.Name = 'testAccount';
        act.Client_Specific_Email__c = 'testtoaddress@gmail.com';
        act.Is_FCP_Customer__c = true;
        act.Parent_Account__c = true;
        act.Domains__c = 'gmail.com';
        Database.insert(act, AccessLevel.SYSTEM_MODE);
        
        List<GetRootAccountPodInvocable.Request> requests = new List<GetRootAccountPodInvocable.Request>();
        GetRootAccountPodInvocable.Request req = new GetRootAccountPodInvocable.Request();
        req.accountId = act.Id;
        requests.add(req);
        
        Test.startTest();
        List<GetRootAccountPodInvocable.Response> responses = GetRootAccountPodInvocable.execute(requests);
        Test.stopTest();
 
        System.assertEquals(1, responses.size());
    }  
}