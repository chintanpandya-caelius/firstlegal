public with sharing class FiscalQuarterService {

    public class QuarterInfo {
		public String quarterKey;
        public Date quarterStart;
        public Date quarterEnd;
    }

    public static QuarterInfo getCurrentQuarter( Date inputDate) {

        QuarterInfo result = new QuarterInfo();
        Integer month = inputDate.month();
        Integer quarterNumber = ((month - 1) / 3) + 1;
        Integer startMonth = ((quarterNumber - 1) * 3) + 1;

        Integer year = inputDate.year();
        Date quarterStart = Date.newInstance(year, startMonth, 1);
        Date quarterEnd = quarterStart.addMonths(3).addDays(-1);
        
        result.quarterStart = quarterStart;
        result.quarterEnd = quarterEnd;
        result.quarterKey = 'FY' + String.valueOf(year) + '-Q' + String.valueOf(quarterNumber);
        return result;
    }
}