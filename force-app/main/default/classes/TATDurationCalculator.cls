/**
 * Pure utility: turn a total number of seconds into Days / Hours / Minutes /
 * Seconds components (1d 2h 30m 15s style) and run elapsed-time math on a
 * Datetime pair, optionally honouring Salesforce Business Hours.
 *
 * Stateless and side-effect free — safe to call from triggers, batches,
 * @AuraEnabled methods, etc.
 */
public with sharing class TATDurationCalculator {

    public class Components {
        public Integer days;
        public Integer hours;
        public Integer minutes;
        public Integer seconds;

        public Components() {
            this.days    = 0;
            this.hours   = 0;
            this.minutes = 0;
            this.seconds = 0;
        }
    }

    /**
     * Break an elapsed seconds total into its D / H / M / S components.
     * Null and negative inputs are treated as zero.
     */
    public static Components decompose(Long totalSeconds) {
        Components c = new Components();
        if (totalSeconds == null || totalSeconds <= 0) {
            return c;
        }

        c.days    = (Integer) (totalSeconds / 86400L);
        Long rem  = Math.mod(totalSeconds, 86400L);
        c.hours   = (Integer) (rem / 3600L);
        rem       = Math.mod(rem, 3600L);
        c.minutes = (Integer) (rem / 60L);
        c.seconds = (Integer) Math.mod(rem, 60L);
        return c;
    }

    /**
     * Wall-clock elapsed seconds between two Datetimes. Returns 0 if either
     * is null or end <= start.
     */
    public static Long elapsedSeconds(Datetime startDt, Datetime endDt) {
        if (startDt == null || endDt == null) return 0L;
        if (endDt <= startDt) return 0L;
        return (endDt.getTime() - startDt.getTime()) / 1000L;
    }

    /**
     * Business-hours elapsed seconds between two Datetimes against the org's
     * default Business Hours record. Returns 0 when no default BH exists,
     * either timestamp is null, or end <= start.
     *
     * @param businessHoursId  optional BusinessHours Id; pass null to use the org default.
     */
    public static Long elapsedBusinessSeconds(Id businessHoursId, Datetime startDt, Datetime endDt) {
        if (startDt == null || endDt == null) return 0L;
        if (endDt <= startDt) return 0L;

        Id bhId = businessHoursId;
        if (bhId == null) {
            List<BusinessHours> defaultBh = [
                SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1
            ];
            if (defaultBh.isEmpty()) return 0L;
            bhId = defaultBh[0].Id;
        }
        Long diffMs = BusinessHours.diff(bhId, startDt, endDt);
        if (diffMs < 0L) return 0L;
        return diffMs / 1000L;
    }
}