/**
 * EDiscoverySLASchedulable
 * ─────────────────────────────────────────────────────────────────────────────
 * NOVA-9004: Scheduled job for eDiscovery SLA monitoring.
 * 
 * Runs every 10 minutes.
 * 
 * Checks:
 *   1. First Response SLA Warning (20 min before breach) → In-App
 *   2. First Response SLA Breach → Email
 *   3. Resolution SLA Breach (30-day target) → Email (Story 7 AC 7.2)
 *
 * Schedule:
 *   System.schedule('eDiscovery SLA Check', '0 0/10 * * * ?', new EDiscoverySLASchedulable());
 * ─────────────────────────────────────────────────────────────────────────────
 */
public class EDiscoverySLASchedulable implements Schedulable {

    private static final String EDISCOVERY_RT = 'EDiscovery';

    public void execute(SchedulableContext ctx) {
        processWarnings();
        processBreaches();
        processResolutionBreaches();
    }

    /**
     * First Response SLA Warning: 20 minutes before breach.
     */
    private void processWarnings() {
        DateTime now = DateTime.now();
        DateTime warningWindow = now.addMinutes(20);

        List<Case> warningCases = [
            SELECT Id, CaseNumber, Subject, OwnerId, Status
            FROM Case
            WHERE RecordType.DeveloperName = :EDISCOVERY_RT
              AND SLA_Breach_DateTime__c > :now
              AND SLA_Breach_DateTime__c <= :warningWindow
              AND SLA_Breach_Warning_Sent__c = false
              AND Status NOT IN ('Resolved', 'Closed')
            LIMIT 200
        ];

        if (warningCases.isEmpty()) return;

        EDiscoveryNotificationHandler.sendSLAWarningNotifications(warningCases);

        List<Case> toUpdate = new List<Case>();
        for (Case c : warningCases) {
            toUpdate.add(new Case(Id = c.Id, SLA_Breach_Warning_Sent__c = true));
        }
        update toUpdate;
    }

    /**
     * First Response SLA Breach: breach time has passed.
     */
    private void processBreaches() {
        DateTime now = DateTime.now();

        List<Case> breachedCases = [
            SELECT Id, CaseNumber, Subject, OwnerId, Status
            FROM Case
            WHERE RecordType.DeveloperName = :EDISCOVERY_RT
              AND SLA_Breach_DateTime__c <= :now
              AND SLA_Breached_Notification_Sent__c = false
              AND Status NOT IN ('Resolved', 'Closed')
            LIMIT 200
        ];

        if (breachedCases.isEmpty()) return;

        EDiscoveryNotificationHandler.sendSLABreachNotifications(breachedCases);

        List<Case> toUpdate = new List<Case>();
        for (Case c : breachedCases) {
            toUpdate.add(new Case(Id = c.Id, SLA_Breached_Notification_Sent__c = true));
        }
        update toUpdate;
    }

    /**
     * Resolution SLA Breach: 30-day resolution target exceeded (Story 7 AC 7.2).
     * Uses CreatedDate + 30 days as the resolution SLA target.
     * Reuses the SLA breach email notification (same recipients: Agent + Supervisor).
     */
    private void processResolutionBreaches() {
        DateTime now = DateTime.now();
        DateTime thirtyDaysAgo = now.addDays(-30);

        List<Case> resolutionBreached = [
            SELECT Id, CaseNumber, Subject, OwnerId, Status
            FROM Case
            WHERE RecordType.DeveloperName = :EDISCOVERY_RT
              AND CreatedDate <= :thirtyDaysAgo
              AND SLA_Breached_Notification_Sent__c = false
              AND Status NOT IN ('Resolved', 'Closed')
            LIMIT 200
        ];

        if (resolutionBreached.isEmpty()) return;

        EDiscoveryNotificationHandler.sendSLABreachNotifications(resolutionBreached);

        List<Case> toUpdate = new List<Case>();
        for (Case c : resolutionBreached) {
            toUpdate.add(new Case(Id = c.Id, SLA_Breached_Notification_Sent__c = true));
        }
        update toUpdate;
    }
}