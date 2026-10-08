@isTest
public class UserTeamRouteToGroupSyncTest {
    
    @isTest
    static void UserTeamRouteToGroupSyncTest_m1(){
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
        
        List<UserTeamRouteToGroupSync.Request> requests = new List<UserTeamRouteToGroupSync.Request>();
        UserTeamRouteToGroupSync.Request req = new UserTeamRouteToGroupSync.Request();
        req.userId = u.Id;
        req.oldValue = null;
        req.newValue = 'FCP POD1;FCP POD2';
        requests.add(req);
        UserTeamRouteToGroupSync.Request req2 = new UserTeamRouteToGroupSync.Request();
        req2.userId = u.Id;
        req2.oldValue = 'FCP POD1';
        req2.newValue = 'FCP POD2';
        requests.add(req2);
        
        UserTeamRouteToGroupSync.syncGroups(requests);
    }
}