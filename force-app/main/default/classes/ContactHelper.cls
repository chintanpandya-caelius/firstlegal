public without sharing class ContactHelper {

    public static void handleBeforeSave(List<Contact> newList, Map<Id, Contact> oldMap) {
        for (Contact con : newList) {
            Contact oldCon = oldMap != null ? oldMap.get(con.Id) : null;

            if (
                oldCon != null &&
                oldCon.Status__c == 'New' &&
                con.Status__c == 'Active' &&
                con.Contact_Start_Date__c == null
            ) {
                con.Contact_Start_Date__c = Date.today();
            }
        }
    }
}