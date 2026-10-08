public with sharing class OpportunityHandler {

    private static final Map<String, String> SERVICE_LINE_MAP = new Map<String, String>{
        'Court & Process' => 'FLCP',
        'Investigations'  => 'FLI',
        'Records'         => 'FRR',
        'E-Discovery'     => 'FLED',
        'Digital'         => 'FLD',
        'Depositions'     => 'FLDS'
    };

    public static void OpportunityNameGenerator(List<Opportunity> newOpps) {
        Set<Id> accountIds = new Set<Id>();

        for (Opportunity opp : newOpps) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }

        Map<Id, Account> accountMap = new Map<Id, Account>(
            [SELECT Id, Name, ShippingStreet FROM Account WHERE Id IN :accountIds]
        );

        for (Opportunity opp : newOpps) {
            if (opp.AccountId == null || !accountMap.containsKey(opp.AccountId)) {
                continue;
            }

            Account acc = accountMap.get(opp.AccountId);

            Integer oppYear = opp.CloseDate != null
                ? opp.CloseDate.year()
                : Date.today().year();

            String serviceAbbr = '';
            if (String.isNotBlank(opp.Service_Line__c)) {
                serviceAbbr = SERVICE_LINE_MAP.get(opp.Service_Line__c);
                if (serviceAbbr == null) {
                    serviceAbbr = 'GEN';
                }
            }

            String streetNum = extractStreetNumber(acc.ShippingStreet);
            String streetLetters = extractStreetLetters(acc.ShippingStreet);

            List<String> parts = new List<String>();
            parts.add(String.valueOf(oppYear));

            if (String.isNotBlank(opp.Matter_Case_Number__c)) {
                parts.add(opp.Matter_Case_Number__c.trim());
            }

            if (String.isNotBlank(serviceAbbr)) {
                parts.add(serviceAbbr);
            }

            if (String.isNotBlank(acc.Name)) {
                parts.add(acc.Name);
            }

            if (String.isNotBlank(streetNum)) {
                parts.add(streetNum);
            }

            if (String.isNotBlank(streetLetters)) {
                parts.add(streetLetters);
            }

            opp.Name = String.join(parts, '-');
        }

        checkForDuplicates(newOpps);
    }

    private static void checkForDuplicates(List<Opportunity> newOpps) {
        Map<Id, Set<String>> namesByAccount = new Map<Id, Set<String>>();
        Set<String> generatedNames = new Set<String>();
        Set<Id> currentOppIds = new Set<Id>();

        for (Opportunity opp : newOpps) {
            if (opp.Id != null) {
                currentOppIds.add(opp.Id);
            }

            if (opp.AccountId != null && String.isNotBlank(opp.Name)) {
                generatedNames.add(opp.Name);

                if (!namesByAccount.containsKey(opp.AccountId)) {
                    namesByAccount.put(opp.AccountId, new Set<String>());
                }

                namesByAccount.get(opp.AccountId).add(opp.Name);
            }
        }

        List<Opportunity> existingOpps = [
            SELECT Id, AccountId, Name
            FROM Opportunity
            WHERE AccountId IN :namesByAccount.keySet()
            AND Name IN :generatedNames
            AND Id NOT IN :currentOppIds
        ];

        Set<String> existingKeys = new Set<String>();

        for (Opportunity existing : existingOpps) {
            existingKeys.add(existing.AccountId + ':' + existing.Name);
        }

        Set<String> inFlightKeys = new Set<String>();

        for (Opportunity opp : newOpps) {
            String key = opp.AccountId + ':' + opp.Name;

            if (existingKeys.contains(key) || inFlightKeys.contains(key)) {
                opp.addError(
                    'An Opportunity with the name "' +
                    opp.Name +
                    '" already exists for this Account.'
                );
            } else {
                inFlightKeys.add(key);
            }
        }
    }

    private static String extractStreetNumber(String street) {
        if (String.isBlank(street)) {
            return '';
        }

        Matcher matcher = Pattern.compile('^\\d+').matcher(street.trim());
        return matcher.find() ? matcher.group(0) : '';
    }

    private static String extractStreetLetters(String street) {
        if (String.isBlank(street)) {
            return '';
        }

        String cleaned = street
            .replaceAll('^[0-9\\s]+', '')
            .replaceAll('[^a-zA-Z]', '');

        return cleaned.length() >= 3
            ? cleaned.substring(0, 3).toUpperCase()
            : cleaned.toUpperCase();
    }
}