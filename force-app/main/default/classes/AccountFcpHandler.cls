public without sharing class AccountFcpHandler {

    public static Boolean bypassForTransaction = false;

    private static final String MSG_FCP_REQUIRED_FIELDS =
        'With FCP Customer set to TRUE, Client Specific Email and Assigned POD are required.';

    public static void runValidation(List<Account> newList) {

        if (bypassForTransaction) {
            return;
        }

        for (Account acc : newList) {

            if (acc.Is_FCP_Customer__c == true) {

                if (String.isBlank(acc.Client_Specific_Email__c)) {
                    acc.Client_Specific_Email__c.addError(
                        MSG_FCP_REQUIRED_FIELDS
                    );
                }

                if (String.isBlank(acc.Assigned_POD__c)) {
                    acc.Assigned_POD__c.addError(
                        MSG_FCP_REQUIRED_FIELDS
                    );
                }

            } else {

                acc.Client_Specific_Email__c = null;
                acc.Assigned_POD__c = null;
            }
        }
    }
}