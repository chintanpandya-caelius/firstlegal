@isTest
private class QueueGroupLinkerTest {

    @isTest
    static void createsLink() {
        Group testQueue = new Group(Name = 'Test Linker Queue', DeveloperName = 'Test_Linker_Queue', Type = 'Queue');
        insert testQueue;
        insert new QueueSobject(QueueId = testQueue.Id, SobjectType = 'Case');

        Group testGroup = new Group(Name = 'Test Linker Group', DeveloperName = 'Test_Linker_Group', Type = 'Regular');
        insert testGroup;

        Queue_Group_Link__mdt mapping = new Queue_Group_Link__mdt(
            Queue_API_Name__c = 'Test_Linker_Queue',
            Group_API_Name__c = 'Test_Linker_Group'
        );

        Test.startTest();
        QueueGroupLinker.LinkResult result = QueueGroupLinker.link(new List<Queue_Group_Link__mdt>{ mapping });
        Test.stopTest();

        System.assertEquals(1, result.linksCreated);
        List<GroupMember> members = [
            SELECT Id FROM GroupMember WHERE GroupId = :testQueue.Id AND UserOrGroupId = :testGroup.Id
        ];
        System.assertEquals(1, members.size());
    }

    @isTest
    static void isIdempotentWhenAlreadyLinked() {
        Group testQueue = new Group(Name = 'Test Idem Queue', DeveloperName = 'Test_Idem_Queue', Type = 'Queue');
        insert testQueue;
        Group testGroup = new Group(Name = 'Test Idem Group', DeveloperName = 'Test_Idem_Group', Type = 'Regular');
        insert testGroup;
        insert new GroupMember(GroupId = testQueue.Id, UserOrGroupId = testGroup.Id);

        Queue_Group_Link__mdt mapping = new Queue_Group_Link__mdt(
            Queue_API_Name__c = 'Test_Idem_Queue',
            Group_API_Name__c = 'Test_Idem_Group'
        );

        Test.startTest();
        QueueGroupLinker.LinkResult result = QueueGroupLinker.link(new List<Queue_Group_Link__mdt>{ mapping });
        Test.stopTest();

        System.assertEquals(0, result.linksCreated);
        System.assertEquals(1, result.alreadyLinked);
    }

    @isTest
    static void skipsMappingWithMissingGroup() {
        Group testQueue = new Group(Name = 'Test Orphan Queue', DeveloperName = 'Test_Orphan_Queue', Type = 'Queue');
        insert testQueue;

        Queue_Group_Link__mdt mapping = new Queue_Group_Link__mdt(
            Queue_API_Name__c = 'Test_Orphan_Queue',
            Group_API_Name__c = 'Does_Not_Exist_Group'
        );

        Test.startTest();
        QueueGroupLinker.LinkResult result = QueueGroupLinker.link(new List<Queue_Group_Link__mdt>{ mapping });
        Test.stopTest();

        System.assertEquals(0, result.linksCreated);
        System.assertEquals(1, result.skippedMissingGroup.size());
    }

    @isTest
    static void skipsMappingWithMissingQueue() {
        Group testGroup = new Group(Name = 'Test Groupless Group', DeveloperName = 'Test_Groupless_Group', Type = 'Regular');
        insert testGroup;

        Queue_Group_Link__mdt mapping = new Queue_Group_Link__mdt(
            Queue_API_Name__c = 'Does_Not_Exist_Queue',
            Group_API_Name__c = 'Test_Groupless_Group'
        );

        Test.startTest();
        QueueGroupLinker.LinkResult result = QueueGroupLinker.link(new List<Queue_Group_Link__mdt>{ mapping });
        Test.stopTest();

        System.assertEquals(0, result.linksCreated);
        System.assertEquals(1, result.skippedMissingQueue.size());
    }

    @isTest
    static void linkAllReadsCustomMetadata() {
        Test.startTest();
        QueueGroupLinker.LinkResult result = QueueGroupLinker.linkAll();
        Test.stopTest();

        System.assertNotEquals(null, result);
    }
}