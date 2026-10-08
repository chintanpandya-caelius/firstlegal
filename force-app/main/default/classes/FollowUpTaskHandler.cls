public with sharing class FollowUpTaskHandler {

    public static void createFollowUpTasks(List<Task> taskList) {

        List<Task> followUpTasks = new List<Task>();

        Set<Id> whatIds = new Set<Id>();
        Set<Id> whoIds = new Set<Id>();

        // Collect Related Record IDs
        for(Task t : taskList){

            if (t.Manual_Followup__c == true) continue;

            Boolean isCall =
                t.TaskSubtype == 'Call' ||
                t.Type == 'Call';

            if(isCall){

                if(t.WhatId != null)
                    whatIds.add(t.WhatId);

                if(t.WhoId != null)
                    whoIds.add(t.WhoId);
            }
        }

        // Prevent duplicate Follow-up Tasks
        Map<String, Task> existingTasks = new Map<String, Task>();

        for(Task t : [
            SELECT Id,
                   WhatId,
                   WhoId,
                   OwnerId
            FROM Task
            WHERE Subject = 'Follow-up Call'
            AND Status != 'Completed'
            AND (
                    WhatId IN :whatIds
                    OR
                    WhoId IN :whoIds
                )
        ]){

            String key =
                String.valueOf(t.OwnerId) +
                String.valueOf(t.WhatId) +
                String.valueOf(t.WhoId);

            existingTasks.put(key, t);
        }

        // Create Follow-up Task
        for(Task callTask : taskList){

            if (callTask.Manual_Followup__c == true) continue;

            Boolean isCall =
                callTask.TaskSubtype == 'Call' ||
                callTask.Type == 'Call';

            if(!isCall)
                continue;

            String key =
                String.valueOf(callTask.OwnerId) +
                String.valueOf(callTask.WhatId) +
                String.valueOf(callTask.WhoId);

            if(existingTasks.containsKey(key))
                continue;

            Task followUp = new Task();

            followUp.Subject = 'Follow-up Call';

            followUp.OwnerId = callTask.OwnerId;

            followUp.Status = 'Not Started';

            followUp.Priority = 'Normal';

            followUp.ActivityDate = System.today().addDays(2);

            followUp.WhatId = callTask.WhatId;

            followUp.WhoId = callTask.WhoId;

            followUpTasks.add(followUp);
        }

        if(!followUpTasks.isEmpty()){
            insert followUpTasks;
        }
    }
}