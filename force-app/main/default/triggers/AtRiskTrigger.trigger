trigger AtRiskTrigger on At_Risk__c (
    after insert,
    after update,
    after delete,
    after undelete
) {
    AtRiskRollupHandler.handle(
        Trigger.isDelete ? null : Trigger.new,
        Trigger.old
    );

    AtRiskTriggerHandler.handle(
        Trigger.isDelete ? null : Trigger.new,
        Trigger.old,
        Trigger.isInsert,
        Trigger.isUpdate,
        Trigger.isDelete,
        Trigger.isUndelete
    );
}