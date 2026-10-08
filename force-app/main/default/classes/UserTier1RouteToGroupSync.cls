public without sharing class UserTier1RouteToGroupSync {

    public class Request {
        @InvocableVariable(required=true)
        public Id userId;
        @InvocableVariable(required=false)
        public String oldValue;
        @InvocableVariable(required=false)
        public String newValue;
    }

    @InvocableMethod(label='UserTier1RouteToGroupSync')
    public static void syncGroups(List<Request> requests) {
        
        Set<String> allDevNames = new Set<String>();
        for (Request req : requests) {
            for (String val : splitPicklist(req.oldValue)) {
                String devName = tier1ValueToGroupDevName(val);
                if (devName != null) allDevNames.add(devName);
            }
            for (String val : splitPicklist(req.newValue)) {
                String devName = tier1ValueToGroupDevName(val);
                if (devName != null) allDevNames.add(devName);
            }
        }

        // Resolve all Group DeveloperNames -> Ids
        Map<String, Id> groupDevNameToId = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName FROM Group
                         WHERE DeveloperName IN :allDevNames WITH SYSTEM_MODE]) {
            groupDevNameToId.put(g.DeveloperName, g.Id);
        }

        List<GroupMember> membersToInsert = new List<GroupMember>();
        List<Id> groupMembersToDeleteQuery = new List<Id>();
        Map<Id, Set<Id>> userIdToGroupsToRemove = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> userIdToGroupsToAdd = new Map<Id, Set<Id>>();
        Set<Id> allUserIds = new Set<Id>();

        for (Request req : requests) {
            Set<String> oldVals = splitPicklist(req.oldValue);
            Set<String> newVals = splitPicklist(req.newValue);

            Set<String> added = new Set<String>(newVals);
            added.removeAll(oldVals);

            Set<String> removed = new Set<String>(oldVals);
            removed.removeAll(newVals);

            Set<Id> groupsToAdd = new Set<Id>();
            for (String val : added) {
                String devName = tier1ValueToGroupDevName(val);
                if (devName != null && groupDevNameToId.containsKey(devName)) {
                    groupsToAdd.add(groupDevNameToId.get(devName));
                }
            }

            Set<Id> groupsToRemove = new Set<Id>();
            for (String val : removed) {
                String devName = tier1ValueToGroupDevName(val);
                if (devName != null && groupDevNameToId.containsKey(devName)) {
                    groupsToRemove.add(groupDevNameToId.get(devName));
                }
            }

            if (!groupsToAdd.isEmpty()) userIdToGroupsToAdd.put(req.userId, groupsToAdd);
            if (!groupsToRemove.isEmpty()) userIdToGroupsToRemove.put(req.userId, groupsToRemove);
            allUserIds.add(req.userId);
        }

        // ADD
        for (Id userId : userIdToGroupsToAdd.keySet()) {
            for (Id groupId : userIdToGroupsToAdd.get(userId)) {
                membersToInsert.add(new GroupMember(GroupId = groupId, UserOrGroupId = userId));
            }
        }
        if (!membersToInsert.isEmpty()) {
            // Avoid duplicate insert errors if membership already exists
            Set<String> existingKeys = new Set<String>();
            for (GroupMember gm : [SELECT GroupId, UserOrGroupId FROM GroupMember
                                    WHERE UserOrGroupId IN :allUserIds WITH SYSTEM_MODE]) {
                existingKeys.add(gm.GroupId + '_' + gm.UserOrGroupId);
            }
            List<GroupMember> filteredInsert = new List<GroupMember>();
            for (GroupMember gm : membersToInsert) {
                String key = gm.GroupId + '_' + gm.UserOrGroupId;
                if (!existingKeys.contains(key)) filteredInsert.add(gm);
            }
            if (!filteredInsert.isEmpty()) Database.insert(filteredInsert, AccessLevel.SYSTEM_MODE);
        }

        // REMOVE
        if (!userIdToGroupsToRemove.isEmpty()) {
            List<GroupMember> existingMembers = [SELECT Id, GroupId, UserOrGroupId FROM GroupMember
                                                  WHERE UserOrGroupId IN :allUserIds WITH SYSTEM_MODE];
            List<GroupMember> toDelete = new List<GroupMember>();
            for (GroupMember gm : existingMembers) {
                Set<Id> removeSet = userIdToGroupsToRemove.get(gm.UserOrGroupId);
                if (removeSet != null && removeSet.contains(gm.GroupId)) {
                    toDelete.add(gm);
                }
            }
            if (!toDelete.isEmpty()) Database.delete(toDelete, AccessLevel.SYSTEM_MODE);
        }
    }
    
    private static String tier1ValueToGroupDevName(String val) {
        if (String.isBlank(val)) return null;
        String result = val.trim().replaceAll('[^a-zA-Z0-9\\s]', '');
        result = result.replaceAll('\\s+', '_');
        return result;
    }

    private static Set<String> splitPicklist(String val) {
        Set<String> result = new Set<String>();
        if (String.isNotBlank(val)) {
            for (String v : val.split(';')) {
                if (String.isNotBlank(v)) result.add(v.trim());
            }
        }
        return result;
    }
}