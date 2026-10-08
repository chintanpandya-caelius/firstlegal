public with sharing class OpportunityContactRoleHandler {

    public static void validateDateRanges(List<OpportunityContactRole> newRecords) {
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (OpportunityContactRole ocr : newRecords) {
            if (ocr.OpportunityId != null && ocr.ContactId != null) {
                opportunityIds.add(ocr.OpportunityId);
                contactIds.add(ocr.ContactId);
            }
        }

        if (opportunityIds.isEmpty()) {
            return;
        }

        // Fetch existing database records to compare against incoming changes
        List<OpportunityContactRole> existingRoles = [
            SELECT Id, OpportunityId, ContactId, Role, Start_Date__c, End_Date__c 
            FROM OpportunityContactRole 
            WHERE OpportunityId IN :opportunityIds 
              AND ContactId IN :contactIds
        ];

        List<OpportunityContactRole> comparisonPool = new List<OpportunityContactRole>(existingRoles);

        for (OpportunityContactRole newRole : newRecords) {
            
            Date newStart = (newRole.Start_Date__c != null) ? newRole.Start_Date__c : Date.newInstance(1900, 1, 1);
            Date newEnd = (newRole.End_Date__c != null) ? newRole.End_Date__c : Date.newInstance(9999, 12, 31);

            for (OpportunityContactRole existingRole : comparisonPool) {
                
                if (newRole.Id != null && newRole.Id == existingRole.Id) {
                    continue;
                }

                if (newRole.OpportunityId == existingRole.OpportunityId &&
                    newRole.ContactId == existingRole.ContactId &&
                    newRole.Role == existingRole.Role) {

                    Date existingStart = (existingRole.Start_Date__c != null) ? existingRole.Start_Date__c : Date.newInstance(1900, 1, 1);
                    Date existingEnd = (existingRole.End_Date__c != null) ? existingRole.End_Date__c : Date.newInstance(9999, 12, 31);

                    if (newStart <= existingEnd && newEnd >= existingStart) {
                        newRole.addError(
                            'A Contact Role already exists for this Contact, Opportunity, and Role during the selected date range. ' +
                            'Please enter an End Date on the active role or adjust your Start Date to avoid overlapping periods.'
                        );
                        break; 
                    }
                }
            }

            comparisonPool.add(newRole);
        }
    }

          
    public static void handleBeforeDelete(List<OpportunityContactRole> oldList) {
        // Evaluate if the running user has the custom deletion restriction assigned (e.g., via Profile or Permission Set)
        Boolean isRestrictedUser = FeatureManagement.checkPermission('Restrict_OCR_Deletion');
        
        if (isRestrictedUser) {
            for (OpportunityContactRole ocr : oldList) {
                ocr.addError(
                    'You are not authorized to delete Contact Roles from this Opportunity. ' +
                    'To retire a contact while preserving historical records, please set an End Date on the record instead.'
                );
            }
        }
    }
}