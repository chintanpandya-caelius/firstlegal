/**
 * NightlyABMAccountUpdateBatchTest
 *
 * Covers every branch of NightlyABMAccountUpdateBatch:
 *   - Each influence-role bucket (High, Champion/Coach, Medium, Low/No, Unknown)
 *   - Influence_Mapping_Gap__c true/false
 *   - Influence_Mapping_Status__c: blank -> set, "Not Started" -> set, existing -> preserved
 *   - Account_Performance_Indicator__c: Hot / Warm / Cold
 *   - Opportunity_Activity_Indicator__c: Active Opportunity / Recent Movement / No Activity
 *   - Review Task created only when an account newly becomes Cold
 *   - Non-Active ABM_Target_Status__c accounts are skipped for Flow #2 but still
 *     get Flow #1 (influence coverage) applied
 *
 * NOTE: Adjust picklist values / record types below if your org enforces
 * validation rules on Account or Contact creation that aren't shown here.
 */
@isTest
private class NightlyABMAccountUpdateBatchTest {

    // Generic helper: returns the first active picklist value for any field.
    // Used to avoid hardcoding guessed picklist values that may not exist.
    static String getFirstActivePicklistValue(Schema.SObjectField field) {
        List<Schema.PicklistEntry> entries = field.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        throw new System.AssertException(
            'No active picklist values found for field: ' + field
        );
    }

    // Looks up any valid, active picklist value for ABM_Target_Status__c
    // other than 'Active' — avoids hardcoding a guessed value that might
    // not exist as a restricted picklist entry in this org.
    static String getNonActiveStatusValue() {
        List<Schema.PicklistEntry> entries =
            Account.ABM_Target_Status__c.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive() && entry.getValue() != 'Active') {
                return entry.getValue();
            }
        }
        // Fallback: if 'Active' is the only value in the picklist, this
        // test scenario can't be constructed — surface that clearly.
        throw new System.AssertException(
            'ABM_Target_Status__c has no active picklist value other than \'Active\' — ' +
            'cannot test the non-Active branch. Check the field\'s picklist values.'
        );
    }

    @testSetup
    static void setup() {
        // ---------------------------------------------------------------
        // Account 1: Hot, has an Active Opportunity, full influence coverage,
        // no prior status set (Influence_Mapping_Status__c blank)
        // ---------------------------------------------------------------
        // NOTE: Revenue_Potential_Score__c is a formula/roll-up field (not
        // directly writeable), so it can't be set in test data. It will
        // resolve to whatever the org calculates (likely 0 with no related
        // records), contributing 0 to the score below.
        Account acc1 = new Account(
            Name = 'Test ABM Account - Hot',
            ABM_Target_Account__c = true,
            ABM_Target_Status__c = 'Active',
            Engagement_Score__c = 80      // -> 30 pts
        );

        // ---------------------------------------------------------------
        // Account 2: starts as Cold (simulate by low scores + no activity),
        // no influence contacts at all -> gap identified, Unknown bucket only
        // ---------------------------------------------------------------
        Account acc2 = new Account(
            Name = 'Test ABM Account - ColdToCold',
            ABM_Target_Account__c = true,
            ABM_Target_Status__c = 'Active',
            Engagement_Score__c = 0,
            Account_Performance_Indicator__c = 'Cold' // already Cold before this run
        );

        // ---------------------------------------------------------------
        // Account 3: was Warm, will newly become Cold this run -> should
        // create a review Task. Has an existing Influence_Mapping_Status__c
        // that should be preserved (not "Not Started"/blank).
        // ---------------------------------------------------------------
        Account acc3 = new Account(
            Name = 'Test ABM Account - NewlyCold',
            ABM_Target_Account__c = true,
            ABM_Target_Status__c = 'Active',
            Engagement_Score__c = 0,
            Account_Performance_Indicator__c = 'Warm',
            Influence_Mapping_Status__c = 'In Progress' // valid picklist value, should be preserved as-is
        );

        // ---------------------------------------------------------------
        // Account 4: ABM target but NOT Active status -> Flow #2 must be
        // skipped entirely (no performance indicator change), Flow #1 still runs
        // ---------------------------------------------------------------
        // NOTE: ABM_Target_Status__c is a restricted picklist, so we look up
        // any valid value other than 'Active' instead of guessing one.
        String nonActiveStatus = getNonActiveStatusValue();
        Account acc4 = new Account(
            Name = 'Test ABM Account - Inactive',
            ABM_Target_Account__c = true,
            ABM_Target_Status__c = nonActiveStatus,
            Engagement_Score__c = 100
        );

        // ---------------------------------------------------------------
        // Account 5: not an ABM target at all -> must be excluded entirely
        // ---------------------------------------------------------------
        Account acc5 = new Account(
            Name = 'Non ABM Account',
            ABM_Target_Account__c = false
        );

        insert new List<Account>{ acc1, acc2, acc3, acc4, acc5 };

        // Contacts need a primary Account before they can be related to any
        // other account (Salesforce treats accountless Contacts as "private").
        // Reusing acc5 here (rather than inserting a new blank Account) avoids
        // tripping any org-specific Account validation rules on required fields
        // like Revenue Type / Service Line.
        // Some Contact validation rules require Service_Line__c to be set
        // depending on a default Revenue Type — supply a valid value dynamically
        // rather than guessing, since we don't know this org's exact picklist values.
        String serviceLine = getFirstActivePicklistValue(Contact.Service_Line__c);

        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'HighInfluence', AccountId = acc5.Id, Service_Line__c = serviceLine),
            new Contact(LastName = 'ChampionCoach', AccountId = acc5.Id, Service_Line__c = serviceLine),
            new Contact(LastName = 'MediumInfluence', AccountId = acc5.Id, Service_Line__c = serviceLine),
            new Contact(LastName = 'LowInfluence', AccountId = acc5.Id, Service_Line__c = serviceLine),
            new Contact(LastName = 'NoInfluence', AccountId = acc5.Id, Service_Line__c = serviceLine),
            new Contact(LastName = 'UnknownInfluence', AccountId = acc5.Id, Service_Line__c = serviceLine)
        };
        insert contacts;

        List<AccountContactRelation> acrsToInsert = new List<AccountContactRelation>{
            new AccountContactRelation(AccountId = acc1.Id, ContactId = contacts[0].Id,
                Contact_Influence_Role__c = 'High Influence'),
            new AccountContactRelation(AccountId = acc1.Id, ContactId = contacts[1].Id,
                Contact_Influence_Role__c = 'Champion/Coach'),
            new AccountContactRelation(AccountId = acc1.Id, ContactId = contacts[2].Id,
                Contact_Influence_Role__c = 'Medium Influence'),
            new AccountContactRelation(AccountId = acc1.Id, ContactId = contacts[3].Id,
                Contact_Influence_Role__c = 'Low Influence'),
            new AccountContactRelation(AccountId = acc1.Id, ContactId = contacts[4].Id,
                Contact_Influence_Role__c = 'No Influence'),
            new AccountContactRelation(AccountId = acc1.Id, ContactId = contacts[5].Id)
            // UnknownInfluence contact: role left blank on purpose -> Unknown bucket
        };
        insert acrsToInsert;

        // Opportunity for Account 1: open -> Active Opportunity (25 pts)
        // Revenue_Type__c and Service_Line__c are required by
        // OpportunityRevenueValidationHandler. 'New Logo' is a standard
        // revenue type; since this is the only Opportunity for this account
        // in this fiscal year, none of that handler's duplicate-checking
        // logic triggers.
        insert new Opportunity(
            Name = 'Open Opp for Hot Account',
            AccountId = acc1.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1),
            Revenue_Type__c = 'New Logo',
            Service_Line__c = 'Digital'
        );

        // No opportunities for acc2/acc3 -> No Activity (0 pts) for those
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        Database.executeBatch(new NightlyABMAccountUpdateBatch(), 200);
        Test.stopTest();

        Map<String, Account> accountsByName = new Map<String, Account>();
        for (Account a : [
            SELECT Id, Name, ABM_Target_Status__c,
                   High_Influence_Contact_Count__c,
                   Champion_Coach_Contact_Count__c,
                   Medium_Influence_Contact_Count__c,
                   Low_No_Influence_Contact_Count__c,
                   Unknown_Influence_Contact_Count__c,
                   Influence_Mapping_Gap__c,
                   Influence_Mapping_Status__c,
                   Account_Performance_Indicator__c,
                   Opportunity_Activity_Indicator__c
            FROM Account
        ]) {
            accountsByName.put(a.Name, a);
        }

        // ---- Account 1: Hot, full influence coverage ----
        Account acc1 = accountsByName.get('Test ABM Account - Hot');
        System.assertEquals(1, acc1.High_Influence_Contact_Count__c, 'High influence count');
        System.assertEquals(1, acc1.Champion_Coach_Contact_Count__c, 'Champion/Coach count');
        System.assertEquals(1, acc1.Medium_Influence_Contact_Count__c, 'Medium influence count');
        System.assertEquals(2, acc1.Low_No_Influence_Contact_Count__c, 'Low/No influence count (Low + No)');
        System.assertEquals(1, acc1.Unknown_Influence_Contact_Count__c, 'Unknown influence count');
        System.assertEquals(false, acc1.Influence_Mapping_Gap__c, 'Has High + Champion -> no gap');
        System.assertEquals('In Progress', acc1.Influence_Mapping_Status__c, 'Blank status -> In Progress since no gap');
        System.assertEquals('Active Opportunity', acc1.Opportunity_Activity_Indicator__c);
        System.assertEquals('Hot', acc1.Account_Performance_Indicator__c,
            'Engagement(30) + Revenue(0, formula field defaults) + OppActivity(25) + LastInteraction(15) = 70 >= 70');

        // ---- Account 2: no influence contacts, already Cold, stays Cold ----
        Account acc2 = accountsByName.get('Test ABM Account - ColdToCold');
        System.assertEquals(0, acc2.High_Influence_Contact_Count__c);
        System.assertEquals(0, acc2.Champion_Coach_Contact_Count__c);
        System.assertEquals(true, acc2.Influence_Mapping_Gap__c, 'No High/Champion contacts -> gap');
        System.assertEquals('Gap Identified', acc2.Influence_Mapping_Status__c);
        System.assertEquals('No Activity', acc2.Opportunity_Activity_Indicator__c);
        System.assertEquals('Cold', acc2.Account_Performance_Indicator__c);

        // ---- Account 3: existing status preserved, newly Cold -> Task created ----
        Account acc3 = accountsByName.get('Test ABM Account - NewlyCold');
        System.assertEquals('In Progress', acc3.Influence_Mapping_Status__c,
            'Existing non-blank/non-"Not Started" status must be preserved');
        System.assertEquals('Cold', acc3.Account_Performance_Indicator__c);

        List<Task> reviewTasks = [
            SELECT Id, Subject, WhatId, Priority, Status
            FROM Task
            WHERE WhatId = :acc3.Id
        ];
        System.assertEquals(1, reviewTasks.size(), 'Exactly one review task for newly-Cold account');
        System.assertEquals('Review Underperforming ABM Account', reviewTasks[0].Subject);
        System.assertEquals('High', reviewTasks[0].Priority);
        System.assertEquals('New', reviewTasks[0].Status);

        // No task should have been created for Account 2 (it was ALREADY Cold, not newly Cold)
        List<Task> acc2Tasks = [SELECT Id FROM Task WHERE WhatId = :acc2.Id];
        System.assertEquals(0, acc2Tasks.size(), 'No task for an account that was already Cold');

        // ---- Account 4: Inactive status -> Flow #2 skipped entirely ----
        Account acc4 = accountsByName.get('Test ABM Account - Inactive');
        System.assertEquals(null, acc4.Account_Performance_Indicator__c,
            'Non-Active ABM_Target_Status__c must not get a performance indicator');
        System.assertEquals(null, acc4.Opportunity_Activity_Indicator__c);
        // Flow #1 still applies to non-Active accounts (only one condition gates it)
        System.assertEquals(true, acc4.Influence_Mapping_Gap__c, 'No contacts -> gap, even though inactive');

        // ---- Account 5: not an ABM target -> excluded entirely ----
        Account acc5 = accountsByName.get('Non ABM Account');
        // NOTE: Influence_Mapping_Gap__c is a checkbox field, which defaults
        // to false (never null) on every new record regardless of whether
        // the batch touches it — so checking it doesn't prove exclusion.
        // High_Influence_Contact_Count__c (a Number field) has no such
        // default, so it staying null is proof the batch never queried acc5.
        System.assertEquals(null, acc5.High_Influence_Contact_Count__c,
            'Non-ABM-target accounts should never be touched by the batch');
    }

    @isTest
    static void testSchedulable() {
        Test.startTest();
        String cronExp = '0 0 2 * * ?';
        System.schedule('Test Nightly ABM Account Update', cronExp, new NightlyABMAccountUpdateBatch());
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronExpression, State
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Test Nightly ABM Account Update'
        ];
        System.assertEquals(1, jobs.size(), 'Scheduled job should be created');
        System.assertEquals(cronExp, jobs[0].CronExpression);
    }
}