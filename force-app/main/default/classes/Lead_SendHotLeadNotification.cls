public with sharing class Lead_SendHotLeadNotification {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public Id ownerId;
    }

    @InvocableMethod(
        label='Send Hot Lead Notification'
        description='Sends SLA breach notifications to Lead Owners or Queue Members.'
    )
    public static void sendNotification(List<Request> requests) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        // Get Notification Type
        CustomNotificationType notificationType;
        try {
            notificationType = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = 'Hot_Lead_SLA_Breach'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Hot Lead SLA Breach Notification Type not found.');
            return;
        }

        // Collect Queue IDs
        Set<Id> queueIds = new Set<Id>();

        for (Request req : requests) {
            if (req.ownerId != null &&
                req.ownerId.getSObjectType() == Group.SObjectType) {

                queueIds.add(req.ownerId);
            }
        }

        // Build Queue -> Users Map
        Map<Id, Set<String>> queueUsers = new Map<Id, Set<String>>();

        if (!queueIds.isEmpty()) {

            for (GroupMember gm : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :queueIds
            ]) {

                if (gm.UserOrGroupId.getSObjectType() == User.SObjectType) {

                    if (!queueUsers.containsKey(gm.GroupId)) {
                        queueUsers.put(gm.GroupId, new Set<String>());
                    }

                    queueUsers.get(gm.GroupId)
                        .add(String.valueOf(gm.UserOrGroupId));
                }
            }
        }

        // Send Notifications
        for (Request req : requests) {

            if (req.ownerId == null || req.leadId == null) {
                continue;
            }

            Set<String> recipients = new Set<String>();

            // User Owner
            if (req.ownerId.getSObjectType() == User.SObjectType) {

                recipients.add(String.valueOf(req.ownerId));

            }

            // Queue Owner
            else if (req.ownerId.getSObjectType() == Group.SObjectType &&
                     queueUsers.containsKey(req.ownerId)) {

                recipients.addAll(queueUsers.get(req.ownerId));

            }

            if (!recipients.isEmpty()) {

                Messaging.CustomNotification notification =
                    new Messaging.CustomNotification();

                notification.setNotificationTypeId(notificationType.Id);

                notification.setTitle(
                    'URGENT: Hot Lead SLA Breached'
                );

                notification.setBody(
                    'A Hot Lead has exceeded its SLA. Click to open the Lead record.'
                );

                notification.setTargetId(req.leadId);

                try {

                    notification.send(recipients);

                } catch (Exception ex) {

                    System.debug(
                        LoggingLevel.ERROR,
                        'Failed sending notification for Lead ' +
                        req.leadId +
                        '. Error: ' +
                        ex.getMessage()
                    );

                }
            }
        }
    }
}