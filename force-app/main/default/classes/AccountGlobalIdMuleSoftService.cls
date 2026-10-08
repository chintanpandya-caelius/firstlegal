/*
* @Author : Rahul Bhavaskar
* @Created Date : 11/09/26
* @Description : Generate Global AccountId MuleSoft Service to Generate GlobalAccountId 
                    from MuleSoft to Salesforce
* @Story Number : 9751
*/
public class AccountGlobalIdMuleSoftService implements Queueable, Database.AllowsCallouts {

    private List<Id> accountIds;
    Map<Id, String> parentAccountIdMap = new Map<Id, String>();
    public AccountGlobalIdMuleSoftService(Id accountId) {
        this.accountIds = new List<Id>{accountId};

        Set<Id> parentAccountIds = new Set<Id>();
        List<Account> accounts = [SELECT Id, ParentId FROM Account WHERE Id = :accountId];
        for(Account acc : accounts) {
            if (acc.ParentId != null) {
            	parentAccountIds.add(acc.ParentId);
        	}
        }
        if (!parentAccountIds.isEmpty()) {
    
            for (Account parentAcc : [
                SELECT Id, accountID__c
                FROM Account
                WHERE Id IN :parentAccountIds
            ]) {
                parentAccountIdMap.put(
                    parentAcc.Id,
                    parentAcc.accountID__c
                );
            }
        }
    }
    
    public static void createAccount(Id account) {
        System.enqueueJob(new AccountGlobalIdMuleSoftService(account));
    }

    public void execute(QueueableContext context) {

        List<Account> accounts =
            [SELECT Id, Name, RecordType.Name,ParentId, BillingAddress, BillingStreet, BillingCity, BillingState, BillingPostalCode
             FROM Account
             WHERE Id IN :accountIds];

        List<Account> accountsToUpdate = new List<Account>();

        for(Account acc : accounts) {

            HttpRequest req = new HttpRequest();
            req.setEndpoint(System.Label.AccountIdentityEndtPointURL );
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('client_id', System.Label.AccountIdentity_Client_id);
            req.setHeader('client_secret', System.Label.AccountIdentity_Client_secret);
            req.setHeader('x-correlation-id', '123');

            Map<String, Object> body = new Map<String, Object>();

            body.put('operation', 'CREATE');

            Map<String, Object> accountMap = new Map<String, Object>();

            accountMap.put('accountName', acc.Name);
            accountMap.put('accountType', acc.RecordType.Name);
            if(acc.ParentId != null){
                accountMap.put('parentAccountId', parentAccountIdMap.get(acc.ParentId));}
            else{
            	accountMap.put('parentAccountId', null);}

            String address =
                acc.BillingStreet + ', ' +
                acc.BillingCity + ', ' +
                acc.BillingState + ' ' +
                acc.BillingPostalCode;

            accountMap.put('address', address);
            
            if(acc.ParentId != null){
                accountMap.put('isParent', false);}
            else{
            	accountMap.put('isParent', true);}
                accountMap.put('forceCreate', true);
                accountMap.put('corporateId', System.Label.MuleSoft_Integration_Corporate_Id);
                accountMap.put('companyId', System.Label.MuleSoft_Integration_Company_Id);
                accountMap.put('customerCode', System.Label.MuleSoft_Integration_Customer_Code);

            body.put('account', accountMap);
            req.setBody(JSON.serialize(body));

            Http http = new Http();
            try {
				
                HttpResponse res = http.send(req);
                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                
                    Map<String, Object> responseMap =
                        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                
                    // Get nested "response" object
                    Map<String, Object> responseData =
                        (Map<String, Object>) responseMap.get('response');
                
                    if (responseData != null) {
                
                        // Get accountId from nested response
                        String accountId = (String) responseData.get('accountId');
                
                        if (String.isNotBlank(accountId)) {
                
                            accountsToUpdate.add(
                                new Account(
                                    Id = acc.Id,
                                    accountID__c = accountId
                                )
                            );
                        }
                    }
                }

            } catch(Exception e) {
                System.debug('First Legal API Error: ' + e.getMessage());
            }
        }

        if(!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}