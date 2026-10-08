@isTest
public class SetupScriptTest {
    
    @isTest
    static void SetupScriptTest_m1(){
        SetupScript.setupQueuesAndGroups();
        SetupScript.setupDivisionalQueuesAndGroups();
        List<Group> QueueRec = [
            SELECT Id, DeveloperName, Type FROM Group
            WHERE DeveloperName = 'FCP_POD1'
            AND type = 'Queue'];
        
        System.assertEquals(1,QueueRec.size());
    }
}