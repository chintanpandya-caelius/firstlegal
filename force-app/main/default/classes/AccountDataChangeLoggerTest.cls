/**
 * Coverage for the AccountDataChangeLogger platform event subscriber trigger.
 *
 * The events are published directly with EventBus.publish rather than by doing
 * DML on Account or Contact and letting the record-triggered flows fire. That
 * matters for two reasons: the test then covers the trigger in isolation and
 * passes whether or not the flows happen to be active in the org, and no
 * Account/Contact records are created, so no flow can publish an extra event
 * and throw the row counts off.
 */
@IsTest
private class AccountDataChangeLoggerTest {

    private static final String CHANGED_OBJECT = 'Account';
    private static final String CHANGE_TYPE    = 'Create';
    private static final String PARENT_ID      = '001000000000001AAA';
    private static final String ACTUAL_ID      = '001000000000001AAA';

    /** Every field on the event is copied onto the log record. */
    @IsTest
    static void singleEvent_createsOneLogWithAllFieldsMapped() {
        Datetime stamp = Datetime.newInstance(2026, 8, 26, 10, 30, 0);

        Test.startTest();
        EventBus.publish(new Account_Data_Change__e(
            ChangedObject__c   = CHANGED_OBJECT,
            ChangeType__c      = CHANGE_TYPE,
            ChangeParentId__c  = PARENT_ID,
            ChangeActualId__c  = ACTUAL_ID,
            ChangeTimestamp__c = stamp
        ));
        Test.stopTest();

        // Forces the event bus to hand the message to the subscriber trigger.
        Test.getEventBus().deliver();

        List<Event_Log__c> logs = [
            SELECT Changed_Object__c, Change_Type__c, Change_Parent_Id__c,
                   Change_Actual_Id__c, Change_Timestamp__c
            FROM Event_Log__c
        ];

        System.assertEquals(1, logs.size(),
            'One published event should produce exactly one Event_Log__c record');
        System.assertEquals(CHANGED_OBJECT, logs[0].Changed_Object__c,
            'ChangedObject__c was not copied to Changed_Object__c');
        System.assertEquals(CHANGE_TYPE, logs[0].Change_Type__c,
            'ChangeType__c was not copied to Change_Type__c');
        System.assertEquals(PARENT_ID, logs[0].Change_Parent_Id__c,
            'ChangeParentId__c was not copied to Change_Parent_Id__c');
        System.assertEquals(ACTUAL_ID, logs[0].Change_Actual_Id__c,
            'ChangeActualId__c was not copied to Change_Actual_Id__c');
        System.assertEquals(stamp, logs[0].Change_Timestamp__c,
            'ChangeTimestamp__c was not copied to Change_Timestamp__c');
    }

    /** The trigger builds a list and inserts once, so a batch must not lose rows. */
    @IsTest
    static void bulkEvents_createOneLogPerEvent() {
        List<Account_Data_Change__e> events = new List<Account_Data_Change__e>();
        for (Integer i = 0; i < 200; i++) {
            events.add(new Account_Data_Change__e(
                ChangedObject__c   = 'Contact',
                ChangeType__c      = 'Update',
                ChangeParentId__c  = '001' + String.valueOf(i).leftPad(15, '0'),
                ChangeActualId__c  = '003' + String.valueOf(i).leftPad(15, '0'),
                ChangeTimestamp__c = System.now()
            ));
        }

        Test.startTest();
        EventBus.publish(events);
        Test.stopTest();

        Test.getEventBus().deliver();

        System.assertEquals(200, [SELECT COUNT() FROM Event_Log__c],
            'Each event in the batch should produce its own Event_Log__c record');
    }

    /** A sparsely populated event must still log, not throw. */
    @IsTest
    static void eventWithEmptyOptionalFields_stillCreatesLog() {
        Test.startTest();
        EventBus.publish(new Account_Data_Change__e(
            ChangedObject__c = 'Contact Point Address',
            ChangeType__c    = 'Update'
            // Ids and timestamp deliberately left null
        ));
        Test.stopTest();

        Test.getEventBus().deliver();

        List<Event_Log__c> logs = [
            SELECT Changed_Object__c, Change_Parent_Id__c, Change_Timestamp__c
            FROM Event_Log__c
        ];

        System.assertEquals(1, logs.size(),
            'An event with null optional fields should still be logged');
        System.assertEquals('Contact Point Address', logs[0].Changed_Object__c,
            'The populated field should still map');
        System.assertEquals(null, logs[0].Change_Parent_Id__c,
            'A null event field should carry through as null');
        System.assertEquals(null, logs[0].Change_Timestamp__c,
            'A null timestamp should carry through as null');
    }
}