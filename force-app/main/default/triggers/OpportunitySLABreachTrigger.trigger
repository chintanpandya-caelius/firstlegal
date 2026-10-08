trigger OpportunitySLABreachTrigger on Opportunity (after update) {

    if (Trigger.isAfter && Trigger.isUpdate) {

        OpportunitySLABreachHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}