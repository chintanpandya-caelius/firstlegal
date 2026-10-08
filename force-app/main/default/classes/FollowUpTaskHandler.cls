public with sharing class FollowUpTaskHandler {

    private static final String FOLLOW_UP_SUBJECT = 'Follow-up Call';
    
    public static void createFollowUpTasks(List<Task> taskList) {
       
        Set<Id> whatIds = new Set<Id>();
        Set<Id> whoIds = new Set<Id>();
        List<Task> callTaskList= new List<Task>();
        Map<String, Task> existingFollowUps = new Map<String, Task>();

        if (taskList == null || taskList.isEmpty()) {
            return;
        }

        // Collect related records for eligible tasks
        for (Task taskRecord: taskList) {
            
            if (taskRecord.TaskSubtype == 'Call' || taskRecord.Type == 'Call') {
                
                Boolean isWhatIdSupported = taskRecord.WhatId != null
                    && (taskRecord.WhatId.getSObjectType() == Account.SObjectType
                    || taskRecord.WhatId.getSObjectType() == Opportunity.SObjectType);

                Boolean isWhoIdSupported = taskRecord.WhoId != null
                    && (taskRecord.WhoId.getSObjectType() == Contact.SObjectType
                    || taskRecord.WhoId.getSObjectType() == Lead.SObjectType);
                
                if (taskRecord.WhatId != null && !isWhatIdSupported) {
                    continue;
                }

                if (taskRecord.WhoId != null && !isWhoIdSupported) {
                    continue;
                }
                
                if (!isWhatIdSupported && !isWhoIdSupported) {
                    continue;
                }
                
                callTaskList.add(taskRecord);
                if (taskRecord.WhatId != null) {
                    whatIds.add(taskRecord.WhatId);
                }

                if (taskRecord.WhoId != null) {
                    whoIds.add(taskRecord.WhoId);
                }

            }
        }

        if (whatIds.isEmpty() && whoIds.isEmpty()) {
            return;
        }

        // Existing active Follow-up Call tasks
        
        List<Task> existingTasks = [SELECT Id, WhatId, WhoId, OwnerId
                                       FROM Task
                                    WHERE Subject = :FOLLOW_UP_SUBJECT
                                    AND Status != 'Completed'
                                    AND (WhatId IN :whatIds OR WhoId IN :whoIds)];
        
        if(existingTasks == null && existingTasks.isEmpty()){
            return;
        }
        
        for (Task existingTask : existingTasks) {
            String key = buildKey(existingTask.OwnerId,existingTask.WhatId,existingTask.WhoId);
            existingFollowUps.put(key, existingTask);
        }

        List<Task> followUpTasks = new List<Task>();

        // Create follow-up tasks
        for (Task sourceTask : callTaskList) {

            // Avoid creating tasks where there is no relationship
            if (sourceTask.WhatId == null && sourceTask.WhoId == null) {
                continue;
            }

            String key = buildKey(sourceTask.OwnerId, sourceTask.WhatId, sourceTask.WhoId);

            // Existing DB task OR another task being created in this transaction
            if (existingFollowUps.containsKey(key)) {
                continue;
            }

            Task followUp = new Task(
                Subject = FOLLOW_UP_SUBJECT,
                OwnerId = sourceTask.OwnerId,
                Status = 'Not Started',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(2),
                WhatId = sourceTask.WhatId,
                WhoId = sourceTask.WhoId
            );

            followUpTasks.add(followUp);

            // Important: prevent duplicates within the current transaction
            existingFollowUps.put(key, followUp);
        }

        if (!followUpTasks.isEmpty()) {
            insert followUpTasks;
        }
    }

    private static String buildKey(Id ownerId, Id whatId, Id whoId) {
        
        String key = String.valueOf(ownerId) + '|' +String.valueOf(whatId) + '|' +  String.valueOf(whoId);
        return key;
    }
}