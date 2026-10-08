trigger EmailMessageTrigger on EmailMessage (before insert, after insert) {

    if (Trigger.isBefore && Trigger.isInsert) {
        EmailMessageTriggerHandler.handleBeforeInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        EmailMessageTriggerHandler.handleAfterInsert(Trigger.new);
    }
}