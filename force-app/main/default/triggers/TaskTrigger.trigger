trigger TaskTrigger on Task (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        FollowUpTaskHandler.createFollowUpTasks(Trigger.new);
    }
}