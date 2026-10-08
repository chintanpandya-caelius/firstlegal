@IsTest
private class AccountOtherRecordHandlerTest {

    // --- SETUP TEST DATA ---
    @TestSetup
    static void setupTestData() {
        // 1. Parent account to avoid Contact private/sharing issues
        Account dummyAcc = new Account(
            Name = 'Dummy Other Parent Account'
        );
        insert dummyAcc;

        // 2. Insert Contact linked to dummy Account
        Contact con = new Contact(
             FirstName = 'Test',
            LastName = 'BillingManager',
            Email = 'billingmanager@example.com',
            AccountId = dummyAcc.Id,
            Department = 'xyz',
            TitleType = 'CEO',
            Phone ='12345678',
            MailingStreet = '123 Main St',
            MailingCity = 'Austin',
            MailingState = 'Alaska',
            MailingStateCode = 'AK',
            MailingPostalCode = '78701',
            MailingCountry = 'United States',
            MailingCountryCode = 'US'
        );
        insert con;
    }

    // Dynamic RecordType Helper
    private static Id getRecordTypeId(String devName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(devName)
            ?.getRecordTypeId();
    }

    // Helper to create fully populated valid Account in memory
    private static Account createValidAccount(String name, String status, String rtDevName) {
        Account acc = new Account(
            Name = name,
            RecordTypeId = getRecordTypeId(rtDevName),
            Status__c = status, 
            
            // Required Detail & Contact Fields
            Email__c = 'main@example.com',
            Fax = '555-0001',
            Phone = '555-0002',
            Shipping_Email__c = 'shipping@example.com',
            Shipping_Fax__c = '555-0003',
            Shipping_Name__c = 'Ship Recipient',
            Shipping_Phone__c = '555-0004',
            Service_Line__c = 'Court & Process', 
            Type = 'Court',

            // Boolean / Checkbox Fields
            Additional_Records_Access__c = false,
            Additional_Web_Access__c = false,
            Address_Is_On_Map__c = true,
            At_Risk__c = false,
            Available_To_Purebred_Website__c = false,
            Delegate_To_All_Contacts__c = false,
            Do_Not_Use__c = false,
            Earns_Points__c = false,
            Finance_Charges__c = false,
            Gifts_Accepted__c = false,
            Group_Invoices__c = false,
            Invoice_Master_Account__c = false,
            Invoice_Print_Option__c = false,
            Override_Points_Earned__c = false,
            Parent_Account__c = false,
            Print_Billing_Tickets__c = false,
            Print_Invoice_Ref_On_Summary__c = false,
            Purebred_Court_Order_Attachment_Required__c = false,
            Receives_Statements__c = false,
            Reference_Required__c = false,
            Revenue_Generator__c = false,
            Separate_Email_Per_Invoice__c = false,
            Single_Job_Invoice_Option__c = false,
            SLA_Breached__c = false,
            Terms__c = false,

            // Common SOR Fields
            Custodian__c = 'John Custodian',
            Default_Date_Weekdays__c = System.today(),
            Default_Service_Date_Friday__c = System.today(),
            Default_Service_Date_Monday__c = System.today(),
            Default_Service_Date_Thursday__c = System.today(),
            Default_Service_Date_Tuesday__c = System.today(),
            Default_Service_Date_Wednesday__c = System.today(),
            Default_Service_Time_Friday__c = Time.newInstance(9, 0, 0, 0),
            Default_Service_Time_Monday__c = Time.newInstance(9, 0, 0, 0),
            Default_Service_Time_Thursday__c = Time.newInstance(9, 0, 0, 0),
            Default_Service_Time_Tuesday__c = Time.newInstance(9, 0, 0, 0),
            Default_Service_Time_Wednesday__c = Time.newInstance(9, 0, 0, 0),
            Default_Time_Weekdays__c = Time.newInstance(9, 0, 0, 0),
            Effective_Date__c = System.today(),
            Expiry_Date__c = System.today().addYears(1),
            Facility_Code__c = 'FAC123',
            Offsite_Comments__c = 'None',
            Source_Customer_ID__c = 'SRC999',
            Source_System__c = 'Datatrac',
            Visiting_Days__c = 'Monday',
            Visiting_Hours__c = '9am-5pm',

            // Datatrac Fields
            Addon_Billing_Amount__c = 10.0,
            Alternate_Lookup_Key__c = 'KEY123',
            Earliest_Delivery_Time__c = Time.newInstance(8, 0, 0, 0),
            Expected_Axis_Delivery_Date__c = System.now(),
            Last_Used_Date__c = System.today(),
            Latest_Delivery_Time__c = Time.newInstance(17, 0, 0, 0),
            Latest_Service_Time__c = Time.newInstance(17, 0, 0, 0),
            Maximum_Daily_Pieces__c = 100,
            Phone_Extension__c = '123',
            Reference__c = 'REF123',
            Special_Instruction_1__c = 'SI1',
            Special_Instruction_2__c = 'SI2',
            Special_Instruction_3__c = 'SI3',
            Special_Instruction_4__c = 'SI4',
            Usage_Count__c = 5,

            // Solaria / Rates Fields
            Location_Rate__c = 15.50,
            Manual_Rate__c = 20.00,
            Special_Rate__c = 12.00,

            // Address Fields
            ShippingStreet = '789 Shipping Rd',
            ShippingCity = 'Austin',
            ShippingState = 'Texas',
            ShippingPostalCode = '78701',
            ShippingCountry = 'United States',
            BillingStreet = '101 Billing Ave',
            BillingCity = 'Austin',
            BillingState = 'Texas',
            BillingPostalCode = '78701',
            BillingCountry = 'United States'
        );
        return acc;
    }

    // Helper to link Contact with Roles
    // NOTE: fixed to query the Contact actually created in @TestSetup
    // (was previously filtering on a non-existent LastName = 'TestContact',
    // which caused a "List has no rows for assignment" exception on every call).
    private static void linkActiveContact(Id accountId) {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'BillingManager' LIMIT 1];
        AccountContactRelation acr = new AccountContactRelation(
            AccountId = accountId,
            ContactId = con.Id,
            Roles = 'Key Decision Maker',
            IsActive = true
        );
        insert acr;
    }

    // Helper to construct a test User with proper permissions
    private static User createAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            Alias = 'admuser',
            Email = 'adminuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'AdminUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'adminuser_' + DateTime.now().getTime() + '@example.com'
        );
        insert u;
        return u;
    }

    // -------------------------------------------------------------------------
    // TEST CASES
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertNewStatusSuccess() {
        Account acc = createValidAccount('New Facility Account', 'New', 'Facility');

        Test.startTest();
        insert acc;
        Test.stopTest();

        System.assertNotEquals(null, acc.Id, 'Account should be successfully inserted');
    }

    @IsTest
    static void testInsertNonNewStatusFails() {
        Account acc = createValidAccount('Active Facility Direct', 'Active', 'Facility');

        Test.startTest();
        Database.SaveResult result = Database.insert(acc, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Direct insertion into Active status without permission/valid setup should fail');
    }

    @IsTest
    static void testBlankStatusDefaultsToProspect() {
        Account acc = createValidAccount('Default Status Court', null, 'Court');

        Test.startTest();
        insert acc;
        Test.stopTest();

        Account refreshed = [SELECT Status__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('New', refreshed.Status__c, 'Blank status should default to New on insert');
    }

    @IsTest
    static void testInvalidStatusTransition() {
        Account acc = createValidAccount('Transition Court', 'New', 'Court');
        insert acc;

        AccountOtherRecordHandler.bypassForTransaction = true;
        acc.Status__c = 'Active';
        update acc;
        AccountOtherRecordHandler.bypassForTransaction = false;

        // Try moving back from Active -> New (Invalid transition)
        acc.Status__c = 'New';

        Test.startTest();
        Database.SaveResult result = Database.update(acc, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Transitioning back to New status should fail');
    }

    @IsTest
    static void testRecordTypeChangeBypassesStatusAndPermissionChecks() {
        User runningUser = createAdminUser();
        System.runAs(runningUser) {
            Account acc = createValidAccount('RT Change Test Account', 'New', 'Court');
            insert acc;

            // Move to Active bypassing validations to setup state
            AccountOtherRecordHandler.bypassForTransaction = true;
            acc.Status__c = 'Active';
            update acc;
            AccountOtherRecordHandler.bypassForTransaction = false;

            // Link contact so required field/contact validations pass
            linkActiveContact(acc.Id);

            // Change Record Type AND set Status to an invalid transition (Active -> New) without permission set
            acc.RecordTypeId = getRecordTypeId('Vendor');
            acc.Status__c = 'New'; 

            Test.startTest();
            Database.SaveResult result = Database.update(acc, false);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess(), 'Record Type change should bypass status transition and permission set enforcement');
        }
    }

    @IsTest
    static void testNewStatusRequiresFields() {
        Account acc = createValidAccount('Incomplete New Account', 'New', 'Facility');
        acc.Shipping_Email__c = null;
        acc.ShippingStreet = null;

        Test.startTest();
        AccountOtherRecordHandler.bypassForTransaction = true;
        insert acc;
        AccountOtherRecordHandler.bypassForTransaction = false;

        acc.Name = 'Updated Name Triggering Field Check';
        Database.SaveResult result = Database.update(acc, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Missing required New status fields should trigger a validation error');
    }

    @IsTest
    static void testActiveStatusSuccessWithContact() {
        User runningUser = createAdminUser();
        System.runAs(runningUser) {
            Account acc = createValidAccount('Active Facility Acc', 'New', 'Facility');
            insert acc;

            linkActiveContact(acc.Id);

            // No bypass here: New -> Active does NOT require the record type's
            // Permission Set (enforceEditPermission is only checked when the
            // OLD status is not 'New'), so real validation runs and should pass.
            acc.Status__c = 'Active';

            Test.startTest();
            Database.SaveResult result = Database.update(acc, false);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess(), 'Valid Active Account with Contact should succeed');
        }
    }

    @IsTest
    static void testActiveStatusMissingContact() {
        User runningUser = createAdminUser();
        System.runAs(runningUser) {
            Account acc = createValidAccount('Active Vendor No Contact', 'New', 'Vendor');
            insert acc;

            // No bypass here so the Contact requirement is actually evaluated.
            acc.Status__c = 'Active';

            Test.startTest();
            Database.SaveResult result = Database.update(acc, false);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'Active Account without linked Contact should fail');
        }
    }

    @IsTest
    static void testFacilityMissingSolariaFields() {
        User runningUser = createAdminUser();
        System.runAs(runningUser) {
            Account acc = createValidAccount('Facility Solaria Test', 'New', 'Facility');
            insert acc;

            linkActiveContact(acc.Id);

            // No bypass here so the Solaria field requirement is actually evaluated.
            acc.Status__c = 'Active';
            acc.Location_Rate__c = null;

            Test.startTest();
            Database.SaveResult result = Database.update(acc, false);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'Facility missing Solaria fields should fail validation');
        }
    }

    @IsTest
    static void testIncompleteAddressValidationOnActive() {
        User runningUser = createAdminUser();
        System.runAs(runningUser) {
            Account acc = createValidAccount('Address Active Test', 'New', 'Professional_Association');
            insert acc;

            linkActiveContact(acc.Id);

            // No bypass here so the Billing address requirement is actually evaluated.
            acc.Status__c = 'Active';
            acc.BillingStreet = null;

            Test.startTest();
            Database.SaveResult result = Database.update(acc, false);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'Incomplete billing address on Active status should fail validation');
        }
    }

    @IsTest
    static void testPermissionSetGroupRestriction() {
        User runningUser = createAdminUser();
        System.runAs(runningUser) {
            Account acc = createValidAccount('Permission Test Court', 'New', 'Court');
            insert acc;

            // Bring the record to Active first (bypassed setup step). Permission
            // enforcement only triggers when the OLD status is not 'New', so we
            // need an already-Active record to actually exercise that check.
            AccountOtherRecordHandler.bypassForTransaction = true;
            acc.Status__c = 'Active';
            update acc;
            AccountOtherRecordHandler.bypassForTransaction = false;

            // Active -> Inactive is an allowed transition, but this user has no
            // PS_Account_RT_Court Permission Set assignment, so it should be blocked.
            acc.Status__c = 'Inactive';

            Test.startTest();
            Database.SaveResult result = Database.update(acc, false);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess(), 'User without required Permission Set should be blocked from status update');
        }
    }

    @IsTest
    static void testBypassFlag() {
        Account acc = createValidAccount('Bypass Other Account', 'New', 'Vendor');
        acc.Shipping_Email__c = null;

        Test.startTest();
        AccountOtherRecordHandler.bypassForTransaction = true;
        Database.SaveResult result = Database.insert(acc, false);
        AccountOtherRecordHandler.bypassForTransaction = false;
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Emergency bypass flag should bypass all validation logic');
    }
}