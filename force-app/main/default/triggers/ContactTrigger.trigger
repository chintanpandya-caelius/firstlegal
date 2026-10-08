trigger ContactTrigger on Contact (before insert, before update) {
    if (Trigger.isBefore) {
        ContactHelper.handleBeforeSave(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
    }
}