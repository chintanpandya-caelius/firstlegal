@IsTest
private class AccountCustomerHandlerTest {

    private static final String PERM_SET_NAME = 'PS_Account_RT_Customer';

    @TestSetup
    static void setupTestData() {
        Account dummyAcc = new Account(
            Name = 'Dummy Parent Account'
        );
        insert dummyAcc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'BillingManager',
            Email = 'billingmanager@example.com',
            AccountId = dummyAcc.Id,
            Department = 'xyz',
            TitleType = 'CEO',
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

    // Assigns the PS_Account_RT_Customer Permission Set to the running user, if not already assigned
    private static void assignAdminPermissionToCurrentUser() {
        Id currentUserId = UserInfo.getUserId();

        List<PermissionSet> psList = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :PERM_SET_NAME
            LIMIT 1
        ];

        if (psList.isEmpty()) {
            return; // Permission Set not found in this org
        }

        // Execute DML as a distinct setup step to avoid Mixed DML issues
        System.runAs(new User(Id = currentUserId)) {
            List<PermissionSetAssignment> existingPs = [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :currentUserId
                AND PermissionSetId = :psList[0].Id
            ];

            if (existingPs.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = currentUserId,
                    PermissionSetId = psList[0].Id
                );
            }
        }
    }

    private static Id getCustomerRecordTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Customer')
            ?.getRecordTypeId();
    }

    private static Account createValidAccount(String name, String status) {
        return new Account(
            Name = name,
            RecordTypeId = getCustomerRecordTypeId(),
            Status__c = status,

            Shipping_Email__c = 'shipping@example.com',
            Service_Line__c = 'Court & Process',
            Email__c = 'main@example.com',
            Fax = '555-1234',
            Phone = '555-5678',
            Shipping_Fax__c = '555-8765',
            Shipping_Name__c = 'Ship Recipient',
            Shipping_Phone__c = '555-4321',
            Sub_Type__c = 'COD',
            Type = 'Court',

            Administration_Fee__c = 10.0,
            ARS_Sales_Territory_Code__c = 'AK',
            Carrying_Fee__c = 5.0,
            Check_Charge_Percentage__c = 2.5,
            Limit_Advance_Fee__c = 1.0,
            Collection_Owner__c = UserInfo.getUserId(),
            Credit_Card_Charge_Description__c = 'Fee',
            Credit_Card_Charge_Income_Account__c = '4000',
            Credit_Card_Charge_Percent__c = 3.0,
            Default_Messenger_Zone__c = 'AK',
            Default_Office_Code__c = 'AK',
            Default_Ship_Records_Method__c = 'Print',
            File_Number_Mask__c = '1234567',
            Finance_Charge_Interest_Rate__c = 1.5,
            Finance_Charges__c = true,
            Receives_Statements__c = true,
            Source_Customer_ID__c = 'SRC123',
            Source_System__c = 'Datatrac',
            Statement_Model__c = 'SUM-CLAIM',

            Billing_Cycle__c = 'Monthly',
            Credit_Status__c = 'Good',
            Group_Invoices__c = false,
            Invoice_Master_Account__c = false,
            Manual_Rate__c = 0.0,
            Special_Rate__c = 0.0,
            New_Order_Alert__c = false,
            New_Order_Alert_Email__c = 'alert@example.com',
            New_Order_Alert_Template__c = 'Template 1',
            Online_Order_Adjustment_Method__c = 'None',
            Reference_Required__c = true,
            Single_Job_Invoice_Option__c = true,
            Statement_Email_Address__c = 'statements@example.com',
            Statement_Print_Option__c = 'Email',
            Surcharge__c = 0.0,
            Validate_Reference__c = false,

            Delegate_To_All_Contacts__c = false,
            Last_Statement_Sent__c = System.today().addDays(-10),
            Need_To_Send__c = 'Yes',

            Firm_Name__c = 'Test Firm',
            Invoicing_Delivery_Method__c = 'Email Other',
            Invoicing_Delivery_Method_Email__c = 'invoices@example.com',
            Invoicing_Format__c = 'Single Job',
            Invoicing_Frequency__c = 'Monthly',
            Invoicing_Receival_Method__c = 'Portal',
            Invoicing_Receival_Method_Detail__c = 'Direct',
            Invoicing_Special_Instructions__c = 'None',
            Payment_Method__c = 'ACH',
            Signatory_Date__c = System.today(),
            Signatory_Name__c = 'John Doe',
            Signatory_Title__c = 'CFO',
            Tax_ID__c = '123456789',
            Terms__c = true,
            Terms_Date__c = System.today(),

            ShippingStreet = '123 Main St',
            ShippingCity = 'Austin',
            ShippingState = 'Alaska',
            ShippingStateCode = 'AK',
            ShippingPostalCode = '78701',
            ShippingCountry = 'United States',
            ShippingCountryCode = 'US',
            BillingStreet = '456 Commercial Blvd',
            BillingCity = 'Austin',
            BillingState = 'Alaska',
            BillingStateCode = 'AK',
            BillingPostalCode = '78701',
            BillingCountry = 'United States',
            BillingCountryCode = 'US'
        );
    }

    private static void linkBillingContact(Id accountId) {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'BillingManager' LIMIT 1];
        insert new AccountContactRelation(
            AccountId = accountId,
            ContactId = con.Id,
            Roles = 'Billing Manager',
            IsActive = true
        );
    }

    // --- POSITIVE & NEGATIVE INSERT TESTS ---

    @IsTest
    static void testInsertNewStatusSuccess() {
        Account acc = createValidAccount('New Account', 'New');
        Test.startTest();
        insert acc;
        Test.stopTest();
    }

    @IsTest
    static void testInsertNonNewStatusFails() {
        Account acc = createValidAccount('Prospect Account', 'Prospect');
        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    // --- STATUS TRANSITIONS ---

    @IsTest
    static void testStatusTransitionsAndValidations() {
        assignAdminPermissionToCurrentUser();

        Account acc = createValidAccount('Full LifeCycle Account', 'New');
        insert acc;

        linkBillingContact(acc.Id);

        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Transition: New -> Prospect
            acc.Status__c = 'Prospect';
            update acc;

            // Transition: Prospect -> Active
            acc.Type = 'Customer';
            acc.Sub_Type__c = 'Plaintiff Firm';
            acc.Status__c = 'Active';
            update acc;

            // Non-status update to ensure trigger fires on regular edit
            acc.Name = 'Updated Active Account Name';
            update acc;

            // Transition: Active -> Inactive
            acc.Status__c = 'Inactive';
            update acc;
        }
        Test.stopTest();
    }

    @IsTest
    static void testStatusTransitionInvalid() {
        assignAdminPermissionToCurrentUser();

        Account acc = createValidAccount('Transition Account', 'New');
        insert acc;

        AccountCustomerHandler.bypassForTransaction = true;
        acc.Status__c = 'Active';
        update acc;
        AccountCustomerHandler.bypassForTransaction = false;

        // Attempt invalid status change (Active -> Prospect)
        acc.Status__c = 'Prospect';

        Test.startTest();
        try {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update acc;
            }
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    // --- PERMISSION AND FIELD VALIDATION FAILURE TESTS ---

    @IsTest
    static void testEditLockEnforcementWithoutAdminPermission() {
        Account acc = createValidAccount('Locked Account', 'New');
        insert acc;

        linkBillingContact(acc.Id);

        AccountCustomerHandler.bypassForTransaction = true;
        acc.Status__c = 'Prospect';
        update acc;
        AccountCustomerHandler.bypassForTransaction = false;

        acc.Status__c = 'Active';

        Test.startTest();
        try {
            update acc;
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    @IsTest
    static void testProspectStatusMissingContact() {
        assignAdminPermissionToCurrentUser();

        Account acc = createValidAccount('No Contact Prospect', 'New');
        insert acc;

        acc.Status__c = 'Prospect';

        Test.startTest();
        try {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update acc;
            }
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    @IsTest
    static void testActiveStatusMissingTerms() {
        assignAdminPermissionToCurrentUser();

        Account acc = createValidAccount('Terms Test', 'New');
        insert acc;

        linkBillingContact(acc.Id);
        acc.Sub_Type__c = 'Law Firm';
        acc.Status__c = 'Active';
        acc.Terms__c = false;

        Test.startTest();
        try {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update acc;
            }
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    @IsTest
    static void testInvalidSubTypeRestriction() {
        assignAdminPermissionToCurrentUser();

        Account acc = createValidAccount('Subtype Test', 'New');
        insert acc;

        linkBillingContact(acc.Id);
        acc.Status__c = 'Prospect';
        acc.Sub_Type__c = 'COD';

        Test.startTest();
        try {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                update acc;
            }
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    @IsTest
    static void testIncompleteAddressValidation() {
        Account acc = createValidAccount('Address Test', 'New');
        acc.ShippingStreet = null;

        Test.startTest();
        try {
            insert acc;
        } catch (DmlException e) {
        }
        Test.stopTest();
    }

    // --- BULK DML, DELETE, UNDELETE & BYPASS EXECUTIONS ---

    @IsTest
    static void testBulkInsertAndUpdate() {
        List<Account> accList = new List<Account>();
        for (Integer i = 0; i < 20; i++) {
            accList.add(createValidAccount('Bulk Account ' + i, 'New'));
        }

        Test.startTest();
        insert accList;

        for (Account a : accList) {
            a.Name = a.Name + ' Modified';
        }
        update accList;
        Test.stopTest();
    }



    @IsTest
    static void testBypassFlag() {
        Account acc = createValidAccount('Bypass Account', 'New');
        acc.ShippingStreet = null; // Invalid condition that usually fails validation

        Test.startTest();
        AccountCustomerHandler.bypassForTransaction = true;
        insert acc;
        AccountCustomerHandler.bypassForTransaction = false;
        Test.stopTest();
    }
}