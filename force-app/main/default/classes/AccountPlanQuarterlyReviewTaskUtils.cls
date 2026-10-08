public with sharing class AccountPlanQuarterlyReviewTaskUtils {
    
    public static Boolean isQuarterStart(Date targetDate) {
        if (targetDate == null) {
            return false;
        }
        Integer month = targetDate.month();
        Integer day = targetDate.day();
        return (day == 1 && (month == 1 || month == 4 || month == 7 || month == 10));
    }

    public static String getReviewInstructions() {
        return 'Please execute the Quarterly Account Plan Review.\n\n' +
               'Instructions:\n' +
               '1. Validate all current Account Plan Objectives.\n' +
               '2. Review open opportunities and pipeline accuracy.\n' +
               '3. Update strategic initiatives based on recent customer engagement.\n' +
               '4. Document outstanding risks, blockers, or competitive threats.\n' +
               '5. Update the Account Plan Status field if adjustments are required.';
    }
}