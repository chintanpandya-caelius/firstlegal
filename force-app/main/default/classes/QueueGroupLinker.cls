public without sharing class QueueGroupLinker {

    public class LinkResult {
        public Integer mappingsProcessed = 0;
        public Integer linksCreated = 0;
        public Integer alreadyLinked = 0;
        public List<String> skippedMissingQueue = new List<String>();
        public List<String> skippedMissingGroup = new List<String>();
    }

    public static LinkResult linkAll() {
        return link([SELECT Queue_API_Name__c, Group_API_Name__c FROM Queue_Group_Link__mdt WITH SYSTEM_MODE]);
    }

    public static LinkResult link(List<Queue_Group_Link__mdt> mappings) {
        LinkResult result = new LinkResult();
        result.mappingsProcessed = mappings.size();

        Set<String> queueDevNames = new Set<String>();
        Set<String> groupDevNames = new Set<String>();
        for (Queue_Group_Link__mdt m : mappings) {
            queueDevNames.add(m.Queue_API_Name__c);
            groupDevNames.add(m.Group_API_Name__c);
        }

        Map<String, Id> queueIdByDevName = new Map<String, Id>();
        Map<String, Id> groupIdByDevName = new Map<String, Id>();
        for (Group g : [
            SELECT Id, DeveloperName, Type
            FROM Group
            WHERE DeveloperName IN :queueDevNames OR DeveloperName IN :groupDevNames
            WITH SYSTEM_MODE
        ]) {
            if (g.Type == 'Queue' && queueDevNames.contains(g.DeveloperName)) {
                queueIdByDevName.put(g.DeveloperName, g.Id);
            } else if (g.Type == 'Regular' && groupDevNames.contains(g.DeveloperName)) {
                groupIdByDevName.put(g.DeveloperName, g.Id);
            }
        }

        Set<Id> queueIds = new Set<Id>(queueIdByDevName.values());
        Set<String> existingMembership = new Set<String>();
        for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE GroupId IN :queueIds WITH SYSTEM_MODE]) {
            existingMembership.add(gm.GroupId + '_' + gm.UserOrGroupId);
        }

        List<GroupMember> toInsert = new List<GroupMember>();
        Set<String> plannedKeys = new Set<String>();

        for (Queue_Group_Link__mdt m : mappings) {
            Id queueId = queueIdByDevName.get(m.Queue_API_Name__c);
            Id groupId = groupIdByDevName.get(m.Group_API_Name__c);

            if (queueId == null) {
                result.skippedMissingQueue.add(m.Queue_API_Name__c);
                continue;
            }
            if (groupId == null) {
                result.skippedMissingGroup.add(m.Group_API_Name__c);
                continue;
            }

            String key = queueId + '_' + groupId;
            if (existingMembership.contains(key)) {
                result.alreadyLinked++;
                continue;
            }
            if (plannedKeys.contains(key)) {
                continue;
            }
            plannedKeys.add(key);
            toInsert.add(new GroupMember(GroupId = queueId, UserOrGroupId = groupId));
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, AccessLevel.SYSTEM_MODE);
        }
        result.linksCreated = toInsert.size();
        System.debug('RESULT::: '+result);
        return result;
    }
}