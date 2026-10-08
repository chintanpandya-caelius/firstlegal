public with sharing class UnresolvedItemsController {

    // Fetch all unresolved email tasks
    @AuraEnabled(cacheable=true)
    public static List<Task> getUnresolvedItems() {
        return [
            SELECT Id, Subject, Description, CreatedDate, Status, Priority 
            FROM Task 
            WHERE Status = 'Open' AND Subject LIKE 'Unresolved Email%'
            ORDER BY CreatedDate DESC
        ];
    }

    // Manually associate an unresolved item to Lead, Contact, Account, or Opportunity
    @AuraEnabled
    public static void associateUnresolvedItem(Id taskId, Id targetRecordId) {
        Task t = [SELECT Id, Subject, Description FROM Task WHERE Id = :taskId LIMIT 1];
        
        String sObjectType = targetRecordId.getSObjectType().getDescribe().getName();

        if (sObjectType == 'Contact' || sObjectType == 'Lead') {
            t.WhoId = targetRecordId; // Assign Name Field
        } else if (sObjectType == 'Account' || sObjectType == 'Opportunity') {
            t.WhatId = targetRecordId; // Assign Related To Field
        }

        t.Status = 'Completed'; // Close unresolved status upon successful association
        update t;
    }

    // Create new Contact and resolve the item directly
    @AuraEnabled
    public static Id createContactAndAssociate(Id taskId, String firstName, String lastName, String email, Id accountId) {
        Contact newContact = new Contact(
            FirstName = firstName,
            LastName = lastName,
            Email = email,
            AccountId = accountId
        );
        insert newContact;

        // Associate the task to the newly created Contact
        associateUnresolvedItem(taskId, newContact.Id);

        return newContact.Id;
    }
}