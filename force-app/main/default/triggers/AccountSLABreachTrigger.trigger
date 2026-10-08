trigger AccountSLABreachTrigger on Account (after update) {

    if (Trigger.isAfter && Trigger.isUpdate) {

        AccountSLABreachHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}