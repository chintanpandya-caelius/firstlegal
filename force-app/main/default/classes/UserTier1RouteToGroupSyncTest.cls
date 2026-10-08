@isTest
public class UserTier1RouteToGroupSyncTest {
    
    @isTest
    static void UserTier1RouteToGroupSyncTest_m1(){
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniqueName = 'testuser' + DateTime.now().getTime() + '@testorg.com';
        
        User u = new User(
            FirstName         = 'Test',
            LastName          = 'User',
            Email             = 'testuser@testorg.com',
            Username          = uniqueName,
            Alias             = 'tuser',
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Tier1_Team__c     = 'FCP POD1'
        );
        Database.insert(u, AccessLevel.SYSTEM_MODE);
        
        List<UserTier1RouteToGroupSync.Request> requests = new List<UserTier1RouteToGroupSync.Request>();
        UserTier1RouteToGroupSync.Request req = new UserTier1RouteToGroupSync.Request();
        req.userId = u.Id;
        req.oldValue = null;
        req.newValue = 'FCP POD1;FCP POD2';
        requests.add(req);
        UserTier1RouteToGroupSync.Request req2 = new UserTier1RouteToGroupSync.Request();
        req2.userId = u.Id;
        req2.oldValue = 'FCP POD1';
        req2.newValue = 'FCP POD2';
        requests.add(req2);
        
        UserTier1RouteToGroupSync.syncGroups(requests);
    }
}