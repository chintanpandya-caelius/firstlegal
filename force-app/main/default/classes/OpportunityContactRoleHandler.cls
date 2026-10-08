public without sharing class OpportunityContactRoleHandler {

    public static void validateDateRanges(List<OpportunityContactRole> newRecords) {
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (OpportunityContactRole ocr : newRecords) {
            if (ocr.OpportunityId != null && ocr.ContactId != null && ocr.Start_Date__c != null) {
                opportunityIds.add(ocr.OpportunityId);
                contactIds.add(ocr.ContactId);
            }
        }

        if (opportunityIds.isEmpty() || contactIds.isEmpty()) {
            return;
        }

        List<OpportunityContactRole> existingRoles = [
            SELECT Id, OpportunityId, ContactId, Start_Date__c, End_Date__c
            FROM OpportunityContactRole
            WHERE OpportunityId IN :opportunityIds
              AND ContactId IN :contactIds
        ];

        // 1. Check against existing database records
        for (OpportunityContactRole newRole : newRecords) {
            if (newRole.OpportunityId == null || newRole.ContactId == null || newRole.Start_Date__c == null) {
                continue;
            }

            Date newStart = newRole.Start_Date__c;
            Date newEnd = newRole.End_Date__c == null ? Date.newInstance(9999, 12, 31) : newRole.End_Date__c;

            if (newEnd < newStart) {
                newRole.addError('End Date cannot be earlier than Start Date.');
                continue;
            }

            for (OpportunityContactRole existingRole : existingRoles) {
                if (newRole.Id != null && newRole.Id == existingRole.Id) {
                    continue;
                }

                if (newRole.OpportunityId == existingRole.OpportunityId && 
                    newRole.ContactId == existingRole.ContactId && 
                    existingRole.Start_Date__c != null) {

                    Date existingStart = existingRole.Start_Date__c;
                    Date existingEnd = existingRole.End_Date__c == null ? Date.newInstance(9999, 12, 31) : existingRole.End_Date__c;

                    if (newStart <= existingEnd && newEnd >= existingStart) {
                        newRole.addError('This Contact already has an Opportunity Contact Role during this date range. Please select a non-overlapping range.');
                        break;
                    }
                }
            }
        }

        // 2. Check in-memory bulk records against each other
        for (Integer i = 0; i < newRecords.size(); i++) {
            OpportunityContactRole firstRole = newRecords[i];
            if (firstRole.OpportunityId == null || firstRole.ContactId == null || firstRole.Start_Date__c == null) continue;

            Date firstStart = firstRole.Start_Date__c;
            Date firstEnd = firstRole.End_Date__c == null ? Date.newInstance(9999, 12, 31) : firstRole.End_Date__c;

            for (Integer j = i + 1; j < newRecords.size(); j++) {
                OpportunityContactRole secondRole = newRecords[j];
                if (secondRole.OpportunityId == null || secondRole.ContactId == null || secondRole.Start_Date__c == null) continue;

                if (firstRole.OpportunityId == secondRole.OpportunityId && firstRole.ContactId == secondRole.ContactId) {
                    Date secondStart = secondRole.Start_Date__c;
                    Date secondEnd = secondRole.End_Date__c == null ? Date.newInstance(9999, 12, 31) : secondRole.End_Date__c;

                    if (firstStart <= secondEnd && firstEnd >= secondStart) {
                        firstRole.addError('Duplicate overlapping record in transaction.');
                        secondRole.addError('Duplicate overlapping record in transaction.');
                    }
                }
            }
        }
    }

    public static void handleBeforeDelete(List<OpportunityContactRole> oldList) {
        // Enforce global no-delete policy for ALL users to preserve audit history
        for (OpportunityContactRole ocr : oldList) {
            ocr.addError('Opportunity Contact Roles cannot be deleted. Please set an End Date to retire the contact role instead.');
        }
    }
}