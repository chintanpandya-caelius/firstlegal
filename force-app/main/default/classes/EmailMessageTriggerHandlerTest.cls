@isTest
public class EmailMessageTriggerHandlerTest {
    
    @isTest
    static void EmailMessageTriggerHandlerTest_m1(){  
        Case cs = new Case();
        cs.Email_Routed__c = false;
        cs.Subject = 'Unittest';
        cs.Status = 'New';
        Database.insert(cs, AccessLevel.SYSTEM_MODE);
        
        Case cs2 = new Case();
        cs2.Email_Routed__c = true;
        cs2.Subject = 'Unittest';
        cs2.Status = 'Closed';
        Database.insert(cs2, AccessLevel.SYSTEM_MODE);
        
        Account act = new Account();
        act.Name = 'testAccount';
        act.Client_Specific_Email__c = 'testtoaddress@gmail.com';
        act.Is_FCP_Customer__c = true;
        act.Parent_Account__c = true;
        act.Domains__c = 'gmail.com';
        Database.insert(act, AccessLevel.SYSTEM_MODE);
        
        Account childAct = new Account();
        childAct.Name = 'testAccount';
        childAct.Client_Specific_Email__c = 'testtoaddress@gmail.com';
        childAct.Is_FCP_Customer__c = true;
        childAct.Parent_Account__c = false;
        childAct.Domains__c = 'gmail.com';
        Database.insert(childAct, AccessLevel.SYSTEM_MODE);
        
        childAct.ParentId = act.Id;
        Database.update(childAct, AccessLevel.SYSTEM_MODE);
        
        Contact ct = new Contact();
        ct.LastName = 'testLastName';
        ct.email = 'testfromaddress@gmail.com';
        ct.AccountId = childAct.Id;
        ct.TitleType = 'individualContributor';
        ct.Department = 'Service';
        Database.insert(ct, AccessLevel.SYSTEM_MODE);
        
        EmailMessage em = new EmailMessage();
        em.FromAddress = 'testfromaddress@gmail.com';
        em.ToAddress = 'testtoaddress@gmail.com';
        em.Subject = 'TEST SUBJECT';
        em.RelatedToId = cs.Id;
        em.Incoming = true;
        Database.insert(em, AccessLevel.SYSTEM_MODE);
        
        EmailMessage em2 = new EmailMessage();
        em2.FromAddress = 'testfromaddress@gmail.com';
        em2.ToAddress = 'testtoaddress@gmail.com';
        em2.Subject = 'TEST SUBJECT';
        em2.RelatedToId = cs2.Id;
        em2.Incoming = true;
        Database.insert(em2, AccessLevel.SYSTEM_MODE);
    }
}