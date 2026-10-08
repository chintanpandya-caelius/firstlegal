trigger LeadSLABreachTrigger on Lead (after update) {

    if (Trigger.isAfter && Trigger.isUpdate) {

        LeadSLABreachHandler.handleAfterUpdate(
            Trigger.new,
            Trigger.oldMap
        );
    }
}