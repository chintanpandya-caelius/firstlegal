global without Sharing class CaseEmailDefaultHandler implements QuickAction.QuickActionDefaultsHandler {

    global void onInitDefaults(QuickAction.QuickActionDefaults[] defaultsList) {
        for (QuickAction.QuickActionDefaults defaults : defaultsList) {
            if (defaults instanceof QuickAction.SendEmailQuickActionDefaults
                && defaults.getTargetSObject().getSObjectType() == EmailMessage.sObjectType) {
                    
                    QuickAction.SendEmailQuickActionDefaults sendEmailDefaults =
                        (QuickAction.SendEmailQuickActionDefaults) defaults;
                    
                    Id contextId = sendEmailDefaults.getContextId();
                    if (contextId != null && contextId.getSObjectType() == Case.SObjectType) {
                        try {
                            String rootAccountEmail = resolveRootAccountOWEA(contextId);
                            if (String.isNotBlank(rootAccountEmail)) {
                                EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
                                emailMessage.ValidatedFromAddress = rootAccountEmail;
                            }
                        } catch (Exception e) {
                            System.debug(LoggingLevel.ERROR, 'Root account email resolution failed: ' + e.getMessage());
                        }
                    }
                }
        }
    }
    
    private String resolveRootAccountOWEA(Id caseId) {
        
        String defaultFSPEmail = System.Label.FirstServiceProgram_Email;
        Case c = [
            SELECT Id, AccountId, ContactId, Contact.AccountId 
            FROM Case 
            WHERE Id = :caseId 
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Id rootSourceAccountId = (c.ContactId != null && c.Contact.AccountId != null)
            ? c.Contact.AccountId
            : c.AccountId;

        if (rootSourceAccountId == null) {
            return defaultFSPEmail;
        }
        Account rootAccount = AccountHierarchyUtil.getRootAccount(
            rootSourceAccountId,
            new Set<String>{ 'Client_Specific_Email__c','Is_FCP_Customer__c' }
        );
        return (rootAccount != null && rootAccount.Is_FCP_Customer__c) ? rootAccount.Client_Specific_Email__c : defaultFSPEmail;
    }
}